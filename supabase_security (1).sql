-- ══════════════════════════════════════════════════════════════════════════════
-- MEDCOLLAB — SUPABASE HARDENING SQL
-- Aplica este archivo en Supabase Dashboard → SQL Editor DESPUÉS del schema base.
-- Reemplaza / endurece las políticas RLS que dejaban al descubierto datos
-- sensibles de la aplicación anterior.
-- ══════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════════
-- 1. PROFILES — separar campos públicos de campos privados/sensibles
-- ══════════════════════════════════════════════════════════════════════════════

-- Añadir campos que faltaban para verificación médica y protección
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone            text,
  ADD COLUMN IF NOT EXISTS pais             text,
  ADD COLUMN IF NOT EXISTS registro_medico  text,
  ADD COLUMN IF NOT EXISTS mfa_enabled      boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_admin         boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_banned        boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at       timestamptz;

-- Vista PÚBLICA: solo campos que cualquier usuario logueado puede ver.
-- No expone email, registro_medico, phone, is_admin, mfa_enabled.
CREATE OR REPLACE VIEW public.profiles_public AS
SELECT
  id,
  full_name,
  especialidad,
  institucion,
  bio,
  avatar_url,
  verified,
  role,
  pais,
  created_at
FROM public.profiles
WHERE is_banned = false AND deleted_at IS NULL;

-- Eliminar la política peligrosa "Perfil visible por todos" y reemplazar
DROP POLICY IF EXISTS "Perfil visible por todos"       ON public.profiles;
DROP POLICY IF EXISTS "Usuario edita su propio perfil" ON public.profiles;
DROP POLICY IF EXISTS "Insertar perfil propio"         ON public.profiles;

-- SELECT: cada usuario solo lee SU FILA completa. Para ver a otros, usa profiles_public.
CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

-- SELECT: perfiles públicos (via vista) accesibles a autenticados
CREATE POLICY "profiles_select_public_via_view"
  ON public.profiles FOR SELECT
  USING (
    auth.role() = 'authenticated' AND
    id IS NOT NULL
  );
-- ↑ Nota: la vista `profiles_public` sirve los datos filtrados; esta política
-- permite el JOIN desde posts/comments para el `profiles:author_id (...)`.
-- Si quieres máxima estrictez, deshabilita esta política y consulta SIEMPRE
-- la vista `profiles_public` desde el frontend.

-- UPDATE: solo campos NO sensibles (nunca role, verified, is_admin, email, id).
-- Se logra con un TRIGGER que revierte cambios en campos protegidos.
CREATE POLICY "profiles_update_own_non_sensitive"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Trigger de blindaje: bloquea intentos de auto-elevación de privilegios
CREATE OR REPLACE FUNCTION public.protect_profile_sensitive_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Campos que NUNCA pueden cambiar por el propio usuario
  IF NEW.role       IS DISTINCT FROM OLD.role       THEN NEW.role       := OLD.role;       END IF;
  IF NEW.verified   IS DISTINCT FROM OLD.verified   THEN NEW.verified   := OLD.verified;   END IF;
  IF NEW.is_admin   IS DISTINCT FROM OLD.is_admin   THEN NEW.is_admin   := OLD.is_admin;   END IF;
  IF NEW.is_banned  IS DISTINCT FROM OLD.is_banned  THEN NEW.is_banned  := OLD.is_banned;  END IF;
  IF NEW.email      IS DISTINCT FROM OLD.email      THEN NEW.email      := OLD.email;      END IF;
  IF NEW.id         IS DISTINCT FROM OLD.id         THEN NEW.id         := OLD.id;         END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN NEW.created_at := OLD.created_at; END IF;
  -- Sanitizar longitudes máximas
  IF length(coalesce(NEW.full_name,''))    > 80  THEN NEW.full_name    := substr(NEW.full_name,1,80);     END IF;
  IF length(coalesce(NEW.especialidad,'')) > 60  THEN NEW.especialidad := substr(NEW.especialidad,1,60);  END IF;
  IF length(coalesce(NEW.institucion,''))  > 100 THEN NEW.institucion  := substr(NEW.institucion,1,100);  END IF;
  IF length(coalesce(NEW.bio,''))          > 300 THEN NEW.bio          := substr(NEW.bio,1,300);          END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile ON public.profiles;
CREATE TRIGGER trg_protect_profile
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_sensitive_fields();

-- INSERT: solo puede insertar SU perfil con datos limpios
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (
    auth.uid() = id AND
    role IN ('medico','estudiante','residente','enfermero') AND  -- roles permitidos por defecto
    verified = false AND                                          -- nunca puede auto-verificarse
    coalesce(is_admin, false) = false
  );


-- ══════════════════════════════════════════════════════════════════════════════
-- 2. POSTS — proteger identidad en publicaciones anónimas
-- ══════════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Posts visibles por todos" ON public.posts;

-- SELECT: todos los usuarios autenticados ven todos los posts,
-- pero se debe consultar via la vista `posts_public` que oculta author_id de anónimos.
CREATE POLICY "posts_select_authenticated"
  ON public.posts FOR SELECT
  USING (auth.role() = 'authenticated');

-- Vista que oculta author_id de posts anónimos (identidad no reversible)
CREATE OR REPLACE VIEW public.posts_public AS
SELECT
  id,
  CASE WHEN anonymous THEN NULL ELSE author_id END AS author_id,
  content,
  anonymous,
  case_type,
  specialty,
  media_url,
  media_type,
  type,
  pulse_type,
  poll_options,
  source_url,
  med_score,
  reach_tier,
  created_at
FROM public.posts;

-- UPDATE / DELETE reforzados
CREATE POLICY "posts_update_own"
  ON public.posts FOR UPDATE
  USING (auth.uid() = author_id) WITH CHECK (auth.uid() = author_id);

-- Bloquear cambio de author_id o de flag anonymous después de creado
CREATE OR REPLACE FUNCTION public.protect_post_fields()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.author_id IS DISTINCT FROM OLD.author_id THEN NEW.author_id := OLD.author_id; END IF;
  IF NEW.anonymous IS DISTINCT FROM OLD.anonymous THEN NEW.anonymous := OLD.anonymous; END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN NEW.created_at := OLD.created_at; END IF;
  -- Limitar longitud
  IF length(coalesce(NEW.content,'')) > 5000 THEN NEW.content := substr(NEW.content,1,5000); END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_posts ON public.posts;
CREATE TRIGGER trg_protect_posts
  BEFORE UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.protect_post_fields();


-- ══════════════════════════════════════════════════════════════════════════════
-- 3. COMMENTS — permitir editar/eliminar propios
-- ══════════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Comentarios visibles"       ON public.comments;
DROP POLICY IF EXISTS "Usuario crea comentario"    ON public.comments;

CREATE POLICY "comments_select_all"
  ON public.comments FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "comments_insert_own"
  ON public.comments FOR INSERT
  WITH CHECK (auth.uid() = author_id AND length(content) <= 2000);

CREATE POLICY "comments_update_own"
  ON public.comments FOR UPDATE
  USING (auth.uid() = author_id) WITH CHECK (auth.uid() = author_id);

CREATE POLICY "comments_delete_own"
  ON public.comments FOR DELETE
  USING (auth.uid() = author_id);


-- ══════════════════════════════════════════════════════════════════════════════
-- 4. NOTIFICATIONS — SOLO el sistema (triggers) puede insertar
-- ══════════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Solo el dueño ve sus notifs" ON public.notifications;

-- SELECT: solo dueño
CREATE POLICY "notifs_select_own"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id);

-- UPDATE (marcar como leída): solo dueño
CREATE POLICY "notifs_update_own"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- DELETE: solo dueño
CREATE POLICY "notifs_delete_own"
  ON public.notifications FOR DELETE
  USING (auth.uid() = user_id);

-- NO política de INSERT desde cliente → solo el service_role/triggers pueden crear.

-- Triggers que crean notifs automáticamente cuando alguien te da like/comenta/sigue
CREATE OR REPLACE FUNCTION public.notify_on_like()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_author uuid; v_liker text;
BEGIN
  SELECT author_id INTO v_author FROM public.posts WHERE id = NEW.post_id;
  IF v_author IS NULL OR v_author = NEW.user_id THEN RETURN NEW; END IF;
  SELECT full_name INTO v_liker FROM public.profiles WHERE id = NEW.user_id;
  INSERT INTO public.notifications(user_id, type, message, ref_id)
  VALUES (v_author, 'like', COALESCE(v_liker,'Un colega') || ' apoyó tu publicación', NEW.post_id);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notif_like ON public.likes;
CREATE TRIGGER trg_notif_like AFTER INSERT ON public.likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_like();

CREATE OR REPLACE FUNCTION public.notify_on_comment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_author uuid; v_cmter text;
BEGIN
  SELECT author_id INTO v_author FROM public.posts WHERE id = NEW.post_id;
  IF v_author IS NULL OR v_author = NEW.author_id THEN RETURN NEW; END IF;
  SELECT full_name INTO v_cmter FROM public.profiles WHERE id = NEW.author_id;
  INSERT INTO public.notifications(user_id, type, message, ref_id)
  VALUES (v_author, 'comment', COALESCE(v_cmter,'Un colega') || ' comentó tu publicación', NEW.post_id);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notif_comment ON public.comments;
CREATE TRIGGER trg_notif_comment AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_comment();

CREATE OR REPLACE FUNCTION public.notify_on_follow()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_follower text;
BEGIN
  SELECT full_name INTO v_follower FROM public.profiles WHERE id = NEW.follower_id;
  INSERT INTO public.notifications(user_id, type, message, ref_id)
  VALUES (NEW.following_id, 'follow', COALESCE(v_follower,'Un colega') || ' te sigue', NEW.follower_id);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notif_follow ON public.follows;
CREATE TRIGGER trg_notif_follow AFTER INSERT ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow();


-- ══════════════════════════════════════════════════════════════════════════════
-- 5. ROOMS + MESSAGES — CONFIDENCIALIDAD MÉDICA (¡crítico!)
-- ══════════════════════════════════════════════════════════════════════════════

-- Tabla de membresía: qué médicos pertenecen a cada sala de urgencias
CREATE TABLE IF NOT EXISTS public.room_members (
  room_id    uuid REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id    uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  role       text DEFAULT 'member', -- 'creator' | 'invited' | 'member'
  joined_at  timestamptz DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);
ALTER TABLE public.room_members ENABLE ROW LEVEL SECURITY;

-- Solo miembros pueden ver la lista de miembros de una sala
CREATE POLICY "room_members_select_if_member"
  ON public.room_members FOR SELECT
  USING (
    auth.uid() = user_id OR
    room_id IN (SELECT room_id FROM public.room_members WHERE user_id = auth.uid())
  );

-- Solo el creador de una sala puede invitar
CREATE POLICY "room_members_insert_by_creator"
  ON public.room_members FOR INSERT
  WITH CHECK (
    auth.uid() = (SELECT created_by FROM public.rooms WHERE id = room_id)
    OR auth.uid() = user_id  -- o usuario se auto-une a sala abierta
  );

-- Rooms: solo ver salas abiertas o de las que soy miembro
DROP POLICY IF EXISTS "Salas visibles"    ON public.rooms;
DROP POLICY IF EXISTS "Médico crea sala"  ON public.rooms;

CREATE POLICY "rooms_select_visible"
  ON public.rooms FOR SELECT
  USING (
    active = true OR
    created_by = auth.uid() OR
    id IN (SELECT room_id FROM public.room_members WHERE user_id = auth.uid())
  );

CREATE POLICY "rooms_insert_own"
  ON public.rooms FOR INSERT
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "rooms_update_creator"
  ON public.rooms FOR UPDATE
  USING (auth.uid() = created_by) WITH CHECK (auth.uid() = created_by);

-- Al crear una sala, agregar automáticamente al creador como miembro
CREATE OR REPLACE FUNCTION public.auto_join_room_creator()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.room_members(room_id, user_id, role)
  VALUES (NEW.id, NEW.created_by, 'creator')
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_auto_join_room ON public.rooms;
CREATE TRIGGER trg_auto_join_room AFTER INSERT ON public.rooms
  FOR EACH ROW EXECUTE FUNCTION public.auto_join_room_creator();

-- MESSAGES — SOLO los miembros de la sala ven los mensajes (crítico para HIPAA/confidencialidad)
DROP POLICY IF EXISTS "Mensajes visibles en sala" ON public.messages;
DROP POLICY IF EXISTS "Médico envía mensaje"      ON public.messages;

CREATE POLICY "messages_select_only_members"
  ON public.messages FOR SELECT
  USING (
    room_id IN (SELECT room_id FROM public.room_members WHERE user_id = auth.uid())
  );

CREATE POLICY "messages_insert_only_members"
  ON public.messages FOR INSERT
  WITH CHECK (
    auth.uid() = author_id AND
    room_id IN (SELECT room_id FROM public.room_members WHERE user_id = auth.uid()) AND
    length(content) <= 4000
  );

CREATE POLICY "messages_delete_own"
  ON public.messages FOR DELETE
  USING (auth.uid() = author_id);


-- ══════════════════════════════════════════════════════════════════════════════
-- 6. HASHTAGS + POST_HASHTAGS — permitir crear desde publish
-- ══════════════════════════════════════════════════════════════════════════════

CREATE POLICY IF NOT EXISTS "hashtags_insert_authenticated"
  ON public.hashtags FOR INSERT
  WITH CHECK (auth.role() = 'authenticated' AND length(tag) BETWEEN 2 AND 40);

CREATE POLICY IF NOT EXISTS "post_hashtags_insert_own_post"
  ON public.post_hashtags FOR INSERT
  WITH CHECK (
    auth.uid() = (SELECT author_id FROM public.posts WHERE id = post_id)
  );


-- ══════════════════════════════════════════════════════════════════════════════
-- 7. PRODUCTS — solo admins pueden modificar
-- ══════════════════════════════════════════════════════════════════════════════

CREATE POLICY IF NOT EXISTS "products_insert_admin"
  ON public.products FOR INSERT
  WITH CHECK (
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
  );

CREATE POLICY IF NOT EXISTS "products_update_admin"
  ON public.products FOR UPDATE
  USING (
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
  );

CREATE POLICY IF NOT EXISTS "products_delete_admin"
  ON public.products FOR DELETE
  USING (
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
  );


-- ══════════════════════════════════════════════════════════════════════════════
-- 8. REPORTS + MODERACIÓN (nueva tabla)
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.reports (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  reporter_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  target_type text NOT NULL, -- 'post' | 'comment' | 'profile' | 'message' | 'room'
  target_id   uuid NOT NULL,
  reason      text NOT NULL, -- 'spam' | 'ofensivo' | 'desinformacion_medica' | 'suplantacion' | 'otro'
  detail      text,
  status      text DEFAULT 'pending', -- 'pending' | 'reviewed' | 'action_taken' | 'dismissed'
  created_at  timestamptz DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES public.profiles(id)
);
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reports_insert_authenticated"
  ON public.reports FOR INSERT
  WITH CHECK (auth.uid() = reporter_id);

CREATE POLICY "reports_select_own_or_admin"
  ON public.reports FOR SELECT
  USING (
    auth.uid() = reporter_id OR
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true
  );

CREATE POLICY "reports_update_admin"
  ON public.reports FOR UPDATE
  USING ((SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true);


-- ══════════════════════════════════════════════════════════════════════════════
-- 9. AUDIT LOG (cumplimiento médico y legal)
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.audit_log (
  id           bigserial PRIMARY KEY,
  actor_id     uuid,
  action       text NOT NULL,           -- 'profile.update','room.create','room.delete','report.action',...
  target_type  text,
  target_id    uuid,
  old_data     jsonb,
  new_data     jsonb,
  ip_address   inet,
  user_agent   text,
  created_at   timestamptz DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_log_select_admin"
  ON public.audit_log FOR SELECT
  USING ((SELECT is_admin FROM public.profiles WHERE id = auth.uid()) = true);

-- Nadie INSERTA desde cliente: solo triggers / edge functions con service_role.


-- ══════════════════════════════════════════════════════════════════════════════
-- 10. STORAGE — bucket privado con URLs firmadas
-- ══════════════════════════════════════════════════════════════════════════════

-- Bucket público sigue siendo aceptable SOLO para avatares y stories generales.
-- Para media clínica y contenido de salas de urgencia usa un bucket PRIVADO.

-- Crear bucket privado para material clínico (si no existe)
INSERT INTO storage.buckets (id, name, public)
VALUES ('medcollab-clinical', 'medcollab-clinical', false)
ON CONFLICT (id) DO NOTHING;

-- Solo el autor puede subir a su carpeta {uid}/
CREATE POLICY IF NOT EXISTS "clinical_upload_own_folder"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'medcollab-clinical' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );

-- Solo el autor y los miembros de la sala pueden leer (aplicar en función SECURITY DEFINER)
CREATE POLICY IF NOT EXISTS "clinical_read_own"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'medcollab-clinical' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );

-- Para servir imágenes clínicas a otros miembros, genera URLs firmadas con
-- expiración corta (5 min) desde tu backend/Edge Function usando service_role.


-- ══════════════════════════════════════════════════════════════════════════════
-- 11. RPC increment_story_views (referenciado en frontend, faltaba)
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.increment_story_views(story_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.stories
     SET views_count = COALESCE(views_count, 0) + 1
   WHERE id = story_id AND expires_at > now();
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════════
-- 12. ÍNDICES DE PERFORMANCE (faltaban)
-- ══════════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_posts_author           ON public.posts(author_id);
CREATE INDEX IF NOT EXISTS idx_posts_created          ON public.posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_specialty        ON public.posts(specialty);
CREATE INDEX IF NOT EXISTS idx_comments_post          ON public.comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_author        ON public.comments(author_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent        ON public.comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_likes_post             ON public.likes(post_id);
CREATE INDEX IF NOT EXISTS idx_likes_user             ON public.likes(user_id);
CREATE INDEX IF NOT EXISTS idx_follows_follower       ON public.follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following      ON public.follows(following_id);
CREATE INDEX IF NOT EXISTS idx_messages_room          ON public.messages(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_user     ON public.notifications(user_id, read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_posts_user       ON public.saved_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_room_members_user      ON public.room_members(user_id);
CREATE INDEX IF NOT EXISTS idx_reports_status         ON public.reports(status, created_at DESC);


-- ══════════════════════════════════════════════════════════════════════════════
-- 13. DASHBOARD: configuración recomendada en Supabase
-- ══════════════════════════════════════════════════════════════════════════════
--
-- Ve a: Authentication → Settings
-- ✓ Enable email confirmations: ON
-- ✓ Enable Multi-Factor Authentication (TOTP): ON  ← recomendado para app médica
-- ✓ Minimum password length: 10
-- ✓ Password requirements: mixed case, numbers, symbols
-- ✓ JWT expiry: 3600 (1 hora)  ← reduce ventana de token robado
-- ✓ Refresh token rotation: Enabled
-- ✓ Reuse interval: 10 seconds
--
-- Ve a: Authentication → Rate Limits
-- ✓ Sign in: 5 por 5 minutos por IP
-- ✓ Sign up: 3 por hora por IP
-- ✓ Password reset: 3 por hora por email
-- ✓ Email OTP: 5 por hora por email
--
-- Ve a: Authentication → URL Configuration
-- ✓ Site URL: https://tudominio.medcollab.co
-- ✓ Redirect URLs: whitelist ESTRICTA (no comodines)
--
-- Ve a: Storage → medcollab-media
-- ✓ Max file size: 50 MB
-- ✓ Allowed MIME types: image/*, video/mp4, video/webm
--
-- Ve a: Database → Backups
-- ✓ Point-in-time recovery: ON (requiere plan Pro+)
-- ✓ Daily backups: retenidos 7-30 días

-- FIN
