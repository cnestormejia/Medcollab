-- ═══════════════════════════════════════════════════════════════════
-- MedCollab — SCHEMA DEFINITIVO alineado con el frontend
-- ⚠️ BORRA todas las tablas de la app y las recrea con columnas correctas.
-- Solo tu tabla profiles y usuarios se conservan.
-- ═══════════════════════════════════════════════════════════════════

DROP TABLE IF EXISTS public.post_hashtags CASCADE;
DROP TABLE IF EXISTS public.hashtags      CASCADE;
DROP TABLE IF EXISTS public.reports       CASCADE;
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.messages      CASCADE;
DROP TABLE IF EXISTS public.room_members  CASCADE;
DROP TABLE IF EXISTS public.rooms         CASCADE;
DROP TABLE IF EXISTS public.story_views   CASCADE;
DROP TABLE IF EXISTS public.stories       CASCADE;
DROP TABLE IF EXISTS public.saved_posts   CASCADE;
DROP TABLE IF EXISTS public.saves         CASCADE;
DROP TABLE IF EXISTS public.follows       CASCADE;
DROP TABLE IF EXISTS public.poll_responses CASCADE;
DROP TABLE IF EXISTS public.comment_likes CASCADE;
DROP TABLE IF EXISTS public.comments      CASCADE;
DROP TABLE IF EXISTS public.likes         CASCADE;
DROP TABLE IF EXISTS public.posts         CASCADE;
DROP TABLE IF EXISTS public.cart_items    CASCADE;
DROP TABLE IF EXISTS public.products      CASCADE;
DROP TABLE IF EXISTS public.push_subscriptions CASCADE;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── POSTS (columnas EXACTAS que usa el frontend) ─────
CREATE TABLE public.posts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content       text NOT NULL,
  type          text DEFAULT 'post',       -- 'post' | 'pulse' | 'case'
  pulse_type    text,                       -- 'opinion' | 'poll' | 'case' | 'perla' | 'link'
  specialty     text,
  case_type     text,
  media_type    text,                       -- 'image' | 'video' | null
  media_url     text,
  poll_options  text,                       -- JSON string con opciones si es poll
  source_url    text,
  anonymous     boolean DEFAULT false,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);
CREATE INDEX idx_posts_author  ON public.posts(author_id);
CREATE INDEX idx_posts_created ON public.posts(created_at DESC);

-- ─── COMMENTS ─────────────────────────────────────
CREATE TABLE public.comments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  author_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  parent_id   uuid REFERENCES public.comments(id) ON DELETE CASCADE,
  content     text NOT NULL,
  created_at  timestamptz DEFAULT now()
);
CREATE INDEX idx_comments_post   ON public.comments(post_id);
CREATE INDEX idx_comments_author ON public.comments(author_id);
CREATE INDEX idx_comments_parent ON public.comments(parent_id);

-- ─── LIKES ────────────────────────────────────────
CREATE TABLE public.likes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  timestamptz DEFAULT now(),
  UNIQUE(post_id, user_id)
);
CREATE INDEX idx_likes_post ON public.likes(post_id);

-- ─── COMMENT_LIKES ────────────────────────────────
CREATE TABLE public.comment_likes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id  uuid NOT NULL REFERENCES public.comments(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  timestamptz DEFAULT now(),
  UNIQUE(comment_id, user_id)
);

-- ─── SAVED_POSTS ──────────────────────────────────
CREATE TABLE public.saved_posts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  saved_at    timestamptz DEFAULT now(),
  UNIQUE(post_id, user_id)
);

-- ─── FOLLOWS ──────────────────────────────────────
CREATE TABLE public.follows (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at     timestamptz DEFAULT now(),
  UNIQUE(follower_id, following_id),
  CHECK (follower_id <> following_id)
);
CREATE INDEX idx_follows_follower  ON public.follows(follower_id);
CREATE INDEX idx_follows_following ON public.follows(following_id);

-- ─── STORIES ──────────────────────────────────────
CREATE TABLE public.stories (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  media_type   text,                       -- 'image' | 'video'
  media_url    text,
  caption      text,
  views        int DEFAULT 0,
  expires_at   timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  created_at   timestamptz DEFAULT now()
);
CREATE INDEX idx_stories_author  ON public.stories(author_id);
CREATE INDEX idx_stories_expires ON public.stories(expires_at);

-- ─── STORY_VIEWS ──────────────────────────────────
CREATE TABLE public.story_views (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id    uuid NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
  viewer_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  viewed_at   timestamptz DEFAULT now(),
  UNIQUE(story_id, viewer_id)
);

-- ─── NOTIFICATIONS ────────────────────────────────
CREATE TABLE public.notifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  from_user_id  uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  type          text NOT NULL,
  post_id       uuid REFERENCES public.posts(id) ON DELETE CASCADE,
  comment_id    uuid REFERENCES public.comments(id) ON DELETE CASCADE,
  read          boolean DEFAULT false,
  created_at    timestamptz DEFAULT now()
);
CREATE INDEX idx_notifs_user ON public.notifications(user_id, created_at DESC);

-- ─── ROOMS (alineado: created_by, priority) ──────
CREATE TABLE public.rooms (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title        text NOT NULL,
  description  text,
  specialty    text,
  priority     text DEFAULT 'moderado',    -- 'critical' | 'urgent' | 'moderate' | 'stable'
  active       boolean DEFAULT true,
  created_at   timestamptz DEFAULT now()
);
CREATE INDEX idx_rooms_created ON public.rooms(created_at DESC);

CREATE TABLE public.room_members (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id    uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at  timestamptz DEFAULT now(),
  UNIQUE(room_id, user_id)
);

-- ─── MESSAGES (alineado: author_id) ───────────────
CREATE TABLE public.messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id    uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  author_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content    text NOT NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX idx_messages_room ON public.messages(room_id, created_at);

-- ─── HASHTAGS ─────────────────────────────────────
CREATE TABLE public.hashtags (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tag          text UNIQUE NOT NULL,
  count        int DEFAULT 0,
  reach_tier   text DEFAULT 'normal',
  created_at   timestamptz DEFAULT now()
);
CREATE TABLE public.post_hashtags (
  post_id     uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  hashtag_id  uuid NOT NULL REFERENCES public.hashtags(id) ON DELETE CASCADE,
  PRIMARY KEY (post_id, hashtag_id)
);

-- ─── PRODUCTS ─────────────────────────────────────
CREATE TABLE public.products (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  price       numeric,
  image_url   text,
  category    text,
  description text,
  active      boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

-- ─── CART_ITEMS (alineado: qty) ───────────────────
CREATE TABLE public.cart_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  product_id  uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  qty         int DEFAULT 1,
  added_at    timestamptz DEFAULT now(),
  UNIQUE(user_id, product_id)
);

-- ─── POLL_RESPONSES (alineado: option_idx) ────────
CREATE TABLE public.poll_responses (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  option_idx  int NOT NULL,
  created_at  timestamptz DEFAULT now(),
  UNIQUE(post_id, user_id)
);

-- ─── PUSH_SUBSCRIPTIONS (alineado: subscription) ──
CREATE TABLE public.push_subscriptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  subscription  jsonb,
  updated_at    timestamptz DEFAULT now()
);

-- ─── REPORTS ──────────────────────────────────────
CREATE TABLE public.reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_type   text NOT NULL,
  target_id     uuid NOT NULL,
  reason        text,
  status        text DEFAULT 'pending',
  created_at    timestamptz DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════════════
-- RLS + POLICIES
-- ═══════════════════════════════════════════════════════════════════
ALTER TABLE public.posts             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comment_likes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_posts       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_views       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_members      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hashtags          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_hashtags     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_responses    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports           ENABLE ROW LEVEL SECURITY;

-- POSTS
CREATE POLICY "posts_select_all" ON public.posts FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "posts_insert_own" ON public.posts FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "posts_update_own" ON public.posts FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "posts_delete_own" ON public.posts FOR DELETE USING (auth.uid() = author_id);

-- COMMENTS (author_id)
CREATE POLICY "comments_select_all" ON public.comments FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "comments_insert_own" ON public.comments FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "comments_update_own" ON public.comments FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "comments_delete_own" ON public.comments FOR DELETE USING (auth.uid() = author_id);

-- LIKES
CREATE POLICY "likes_select_all" ON public.likes FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "likes_insert_own" ON public.likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "likes_delete_own" ON public.likes FOR DELETE USING (auth.uid() = user_id);

-- COMMENT_LIKES
CREATE POLICY "clikes_select_all" ON public.comment_likes FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "clikes_insert_own" ON public.comment_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "clikes_delete_own" ON public.comment_likes FOR DELETE USING (auth.uid() = user_id);

-- SAVED_POSTS
CREATE POLICY "saved_own" ON public.saved_posts FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- FOLLOWS
CREATE POLICY "follows_select_all" ON public.follows FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "follows_insert_own" ON public.follows FOR INSERT WITH CHECK (auth.uid() = follower_id);
CREATE POLICY "follows_delete_own" ON public.follows FOR DELETE USING (auth.uid() = follower_id);

-- STORIES
CREATE POLICY "stories_select_all" ON public.stories FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "stories_insert_own" ON public.stories FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "stories_delete_own" ON public.stories FOR DELETE USING (auth.uid() = author_id);

-- STORY_VIEWS
CREATE POLICY "sv_select_all" ON public.story_views FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "sv_insert_own" ON public.story_views FOR INSERT WITH CHECK (auth.uid() = viewer_id);

-- NOTIFICATIONS
CREATE POLICY "notifs_select_own" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "notifs_insert_all" ON public.notifications FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "notifs_update_own" ON public.notifications FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "notifs_delete_own" ON public.notifications FOR DELETE USING (auth.uid() = user_id);

-- ROOMS (created_by)
CREATE POLICY "rooms_select_all" ON public.rooms FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "rooms_insert_own" ON public.rooms FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "rooms_update_creator" ON public.rooms FOR UPDATE USING (auth.uid() = created_by);
CREATE POLICY "rooms_delete_creator" ON public.rooms FOR DELETE USING (auth.uid() = created_by);

-- ROOM_MEMBERS
CREATE POLICY "rm_select_all" ON public.room_members FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "rm_insert_self" ON public.room_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "rm_delete_self" ON public.room_members FOR DELETE USING (auth.uid() = user_id);

-- MESSAGES (author_id)
CREATE POLICY "msg_select_all" ON public.messages FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "msg_insert_own" ON public.messages FOR INSERT WITH CHECK (auth.uid() = author_id);

-- HASHTAGS
CREATE POLICY "hashtags_select_all" ON public.hashtags FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "hashtags_insert_all" ON public.hashtags FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- POST_HASHTAGS
CREATE POLICY "ph_select_all" ON public.post_hashtags FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "ph_insert_own" ON public.post_hashtags FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.posts WHERE id = post_id AND author_id = auth.uid()));

-- PRODUCTS
CREATE POLICY "products_select_all" ON public.products FOR SELECT USING (true);

-- CART_ITEMS
CREATE POLICY "cart_own" ON public.cart_items FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- POLL_RESPONSES (option_idx)
CREATE POLICY "polls_select_all" ON public.poll_responses FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "polls_insert_own" ON public.poll_responses FOR INSERT WITH CHECK (auth.uid() = user_id);

-- PUSH_SUBSCRIPTIONS
CREATE POLICY "push_own" ON public.push_subscriptions FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- REPORTS
CREATE POLICY "reports_insert_own" ON public.reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
CREATE POLICY "reports_select_own" ON public.reports FOR SELECT USING (auth.uid() = reporter_id);

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIONES RPC
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.cleanup_expired_stories();
CREATE FUNCTION public.cleanup_expired_stories()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c int;
BEGIN
  WITH d AS (DELETE FROM public.stories WHERE expires_at < now() RETURNING id)
  SELECT count(*) INTO c FROM d;
  RETURN c;
END;
$$;

DROP FUNCTION IF EXISTS public.increment_story_views(uuid);
CREATE FUNCTION public.increment_story_views(story_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.stories SET views = views + 1 WHERE id = story_id;
  INSERT INTO public.story_views (story_id, viewer_id)
  VALUES (story_id, auth.uid())
  ON CONFLICT (story_id, viewer_id) DO NOTHING;
END;
$$;

DROP FUNCTION IF EXISTS public.suggest_doctors(uuid, int);
CREATE FUNCTION public.suggest_doctors(user_id uuid, limit_count int DEFAULT 10)
RETURNS TABLE(id uuid, full_name text, avatar_url text, especialidad text, followers_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name, p.avatar_url, p.especialidad,
    (SELECT count(*) FROM public.follows WHERE following_id = p.id) AS fc
  FROM public.profiles p
  WHERE p.id != user_id
    AND p.id NOT IN (SELECT following_id FROM public.follows WHERE follower_id = user_id)
  ORDER BY fc DESC, p.created_at DESC
  LIMIT limit_count;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- REALTIME
-- ═══════════════════════════════════════════════════════════════════
DO $$ BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;      EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;         EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.room_members;  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.posts;         EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- REPORTE
-- ═══════════════════════════════════════════════════════════════════
SELECT table_name,
  (SELECT count(*) FROM pg_policies WHERE tablename = t.table_name AND schemaname='public') AS policies
FROM information_schema.tables t
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;
