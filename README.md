# MedCollab

> La red social de la comunidad médica latinoamericana.

Plataforma web para que médicos y profesionales de la salud compartan casos clínicos, coordinen salas de urgencia en tiempo real, publiquen opiniones ("Pulses"), asistan a conferencias virtuales y accedan a una tienda de material médico.

## Stack

- **Frontend:** HTML monolítico + CSS + JS vanilla (sin build step)
- **Backend:** Supabase (PostgreSQL + Auth + Storage + Realtime)
- **Hosting recomendado:** Netlify o Vercel con Cloudflare al frente
- **Auth:** Email + OAuth (Google, Apple, Meta), con MFA opcional

## Features actuales

- Feed con posts, comentarios, likes, saves, hashtags
- Historias efímeras (24h) tipo Instagram
- Salas de urgencia con chat en tiempo real
- Perfil con verificación KYC (pendiente integración Truora + RETHUS)
- Tienda de material médico (pendiente integración Stripe)
- Notificaciones in-app y push (pendiente OneSignal)
- Panel de conferencias y eventos
- Sistema de MedScore y ranking

## Estructura del repo

```
medcollab/
├── medcollab_secure.html    # App completa (frontend monolítico)
├── supabase_security.sql    # Schema + RLS + triggers para Supabase
├── SECURITY_AUDIT.docx      # Reporte de auditoría de seguridad
├── INTEGRATIONS_PLAN.docx   # Plan de integraciones externas por fases
├── .gitignore
└── README.md
```

## Setup local

### 1. Crear proyecto en Supabase

Ve a [supabase.com](https://supabase.com) → New project → región **South America (São Paulo)**. Anota:
- Project URL (formato `https://xxxxxx.supabase.co`)
- anon public key

### 2. Ejecutar el SQL de seguridad

En Supabase Dashboard → SQL Editor → New query → pega todo el contenido de `supabase_security.sql` → Run.

### 3. Configurar credenciales

Abre `medcollab_secure.html` en un editor y reemplaza:

```javascript
const SUPA_URL = 'https://TU_PROYECTO.supabase.co';
const SUPA_KEY = 'TU_ANON_KEY_AQUI';
```

⚠️ **NO subas este archivo con credenciales reales al repo.** La `anon key` es técnicamente pública, pero es mejor práctica mantenerla fuera del control de versiones.

### 4. Configurar Supabase Dashboard

Sigue las instrucciones al final de `supabase_security.sql`:
- Authentication → Providers: activar Confirm email, Secure email change
- Authentication → Multi-factor: activar TOTP
- Authentication → Rate Limits: ajustar según tráfico esperado
- Storage: crear buckets `medcollab-media` (public) y `medcollab-clinical` (private)

### 5. Servir el archivo

**Opción A — Netlify (recomendado):**
```
Arrastra la carpeta a netlify.com → Deploy manually
```

**Opción B — Localhost:**
```
python3 -m http.server 8000
# Abre http://localhost:8000/medcollab_secure.html
```

**Opción C — Doble clic** (limitado — algunas features fallan por CORS con `file://`).

## Seguridad

Este proyecto pasó por una auditoría interna. Ver `SECURITY_AUDIT.docx` para el detalle completo. Hallazgos y mitigaciones:

- ✅ **XSS**: todos los inputs de usuario se sanitizan antes de insertar en DOM
- ✅ **CSP + cabeceras**: Content-Security-Policy, X-Content-Type-Options, Referrer-Policy
- ✅ **RLS estricto**: mensajes de salas solo visibles a miembros; usuarios no pueden auto-elevar rol/verificado
- ✅ **Rate limiting**: persistente en localStorage
- ✅ **Validación de archivos**: whitelist de MIME + tamaño + magic bytes
- ✅ **Contraseñas fuertes**: mínimo 10 chars con requisitos
- ✅ **OAuth pinneado**: `redirectTo` solo al origin propio

Pendientes documentados en `INTEGRATIONS_PLAN.docx`.

## Roadmap de integraciones

Ver `INTEGRATIONS_PLAN.docx` para pasos detallados. Resumen:

**Fase 1 (crítico):** Netlify → Cloudflare → Supabase config → Resend (email) → Truora/RETHUS (verificación médica) → Términos y privacidad (Ley 1581)

**Fase 2 (importante):** Sentry (errores) → PostHog (analytics) → OneSignal (push)

**Fase 3 (opcional):** Daily.co (video) → Stripe (pagos) → Meilisearch (búsqueda) → Mux (video hosting) → Claude API (asistente clínico)

## Cumplimiento legal

Al operar en Colombia, esta plataforma debe cumplir:
- **Ley 1581 de 2012** (Protección de datos personales / Habeas Data)
- **Registro de bases de datos ante SIC** si supera 100k titulares
- **Consentimientos in-app** para tratamiento de datos sensibles (salud)
- **Términos de uso** que aclaren que la plataforma NO reemplaza consulta médica

## Contribuciones

Este es un repositorio privado. Para colaborar, contactar al propietario.

## Licencia

Propietario — todos los derechos reservados. No distribuir sin autorización.

---

**Contacto:** SCALIFY · Valledupar, Colombia
