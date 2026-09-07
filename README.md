# MedCollab

> La red social profesional de la comunidad médica latinoamericana.

Plataforma web para médicos y personal de salud: intercambio de casos clínicos anonimizados, salas de urgencia con chat en tiempo real, historias efímeras, opiniones tipo "Pulse", conferencias y tienda de material médico.

**🌐 Producción:** [medcollab-two.vercel.app](https://medcollab-two.vercel.app)

---

## Stack

- **Frontend:** HTML monolítico + CSS + JS vanilla (sin build step, sin dependencias de compilación)
- **Backend:** Supabase — PostgreSQL + Auth + Storage + Realtime
- **Hosting:** Vercel con auto-deploy desde GitHub
- **Auth:** Email + OAuth (Google, Apple, Meta), MFA opcional (TOTP)

---

## Estructura del repo

```
Medcollab/
├── index.html                   # App completa (frontend monolítico)
├── RESET_FINAL_SCHEMA.sql       # Schema SQL alineado con el frontend
├── fix_avatars_bucket.sql       # Policies del bucket avatars
├── SECURITY_AUDIT.docx          # Auditoría de seguridad
├── INTEGRATIONS_PLAN.docx       # Plan de integraciones externas
├── .gitignore
├── .env.example
└── README.md
```

---

## Features implementadas

- ✅ Feed con posts (tipo `post`, `pulse`, `case`, `perla`), likes, comentarios anidados, saves
- ✅ Historias efímeras (24h) filtradas por médicos que sigues
- ✅ Salas de urgencia con chat en tiempo real (Realtime WebSocket)
- ✅ Perfil médico (pendiente verificación Truora/RETHUS)
- ✅ Panel de notificaciones in-app
- ✅ Sistema de MedScore y ranking de reach por hashtag
- ✅ Registro/Login email + OAuth (Google/Apple/Meta)
- ✅ Modales legales integrados: Términos, Privacidad (Ley 1581), Ética médica
- ✅ Banner de cookies con opt-in granular
- ✅ Sección Habeas Data: exportar datos (JSON), cerrar sesión, eliminar cuenta

## Pendiente de integración

- ⏳ Verificación RETHUS/Truora (KYC médico real)
- ⏳ Push notifications (OneSignal)
- ⏳ Videoconferencia real (Daily.co) — hoy los botones LIVE son placeholders
- ⏳ Pagos en Tienda (Stripe)
- ⏳ Email transaccional (Resend)

Ver `INTEGRATIONS_PLAN.docx` para el paso a paso de cada uno.

---

## Setup local

### 1. Crear proyecto en Supabase

Ve a [supabase.com](https://supabase.com) → **New project** → región **South America (São Paulo)**. Guarda:
- **Project URL** (formato `https://xxxxxx.supabase.co`)
- **anon public key**

### 2. Ejecutar el schema

En Supabase Dashboard → **SQL Editor** → New query → pega TODO el contenido de `RESET_FINAL_SCHEMA.sql` → **Run**.

⚠️ Este script hace `DROP TABLE ... CASCADE` sobre las tablas de la app. Solo úsalo en un proyecto nuevo o si aceptas perder los datos existentes.

### 3. Configurar credenciales en el HTML

Abre `index.html` en un editor y reemplaza:

```javascript
const SUPA_URL = 'https://TU_PROYECTO.supabase.co';
const SUPA_KEY = 'TU_ANON_KEY_AQUI';
```

⚠️ **No hagas commit del HTML con credenciales reales** al repo público. La `anon key` es técnicamente pública (funciona como llave del cliente), pero es mejor práctica versionar solo la versión con placeholders.

### 4. Configurar Supabase Dashboard

- **Authentication → Providers**: activar Confirm email
- **Authentication → Multi-factor**: activar TOTP
- **Storage → New bucket**: crear `avatars` (public) y `medcollab-media` (public)
- Ejecutar `fix_avatars_bucket.sql` para las policies del bucket avatars

### 5. Servir el archivo

**Opción A — Deploy en Vercel/Netlify (recomendado):**
- Fork el repo → conectar a Vercel/Netlify → auto-deploy con cada push

**Opción B — Localhost:**
```bash
python3 -m http.server 8000
# Abrir http://localhost:8000
```

---

## Diagnóstico en producción

La app incluye una función global para debuggear el estado:

1. Abre la app → login
2. F12 → Console
3. Ejecuta: `mcDebug()`

Retorna el estado de conexión con Supabase, del usuario actual, y ejecuta un INSERT/DELETE de prueba en `posts` para verificar que las RLS permiten operaciones.

Un banner verde en la esquina superior derecha muestra la versión desplegada — útil para confirmar que no estás viendo caché viejo del navegador.

---

## Seguridad

Ver `SECURITY_AUDIT.docx` para el reporte completo.

- ✅ **XSS**: todos los inputs de usuario se sanitizan antes de insertar en DOM
- ✅ **CSP + cabeceras**: Content-Security-Policy, X-Content-Type-Options, Referrer-Policy
- ✅ **RLS estricto**: cada tabla con policies granulares; users no pueden auto-elevar rol
- ✅ **Rate limiting**: persistente en localStorage
- ✅ **Validación de archivos**: MIME whitelist + tamaño + magic bytes
- ✅ **Contraseñas fuertes**: mínimo 10 chars con requisitos
- ✅ **OAuth pinneado**: `redirectTo` solo al origin propio
- ✅ **Habeas Data**: exportar y borrar cuenta funcionales

---

## Cumplimiento legal (Colombia)

- **Ley 1581 de 2012** (Habeas Data): consentimiento explícito, derechos ARCO+, exportar/borrar cuenta implementados
- **Registro de bases de datos ante SIC**: requerido si se superan 100k titulares (trámite externo)
- **Ley 23 de 1981** (Ética médica): código de ética in-app disponible
- **Disclaimer médico permanente**: "El contenido NO es consulta médica ni sustituye el juicio clínico presencial" visible en el feed

Los textos legales incluidos son plantillas base y deben ser revisados por un abogado especializado en derecho digital y de la salud antes del lanzamiento oficial.

---

## Roadmap por fases

Ver `INTEGRATIONS_PLAN.docx` para detalle.

**Fase 1 (crítico):** Cloudflare (WAF+CDN) → Resend (email) → Truora + RETHUS (KYC médico) → Términos/Privacidad revisados por abogado

**Fase 2 (importante):** Sentry (errores) → PostHog (analytics) → OneSignal (push)

**Fase 3 (opcional):** Daily.co (video) → Stripe (pagos) → Meilisearch (búsqueda) → Mux (video hosting) → Claude API (asistente clínico)

---

## Contribuciones

Repositorio privado. Contactar al propietario para colaborar.

## Licencia

Propietario — todos los derechos reservados. No distribuir sin autorización.

---

**Contacto:** SCALIFY · Valledupar, Colombia
