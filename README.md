# NOVARYX AI

NOVARYX AI is an AI creative studio with a responsive website and an Android app. The website provides separate image, video, and music generation workspaces, Supabase authentication, user credits, cloud history, and background task tracking while the browser session remains active.

## Website

The Render service serves the website from `backend/public/index.html`. The root `Dockerfile` starts `backend/server.js`.

Website capabilities:
- Supabase email/password registration and login.
- Image generation with text-to-image and image-to-image modes.
- Video generation with text-to-video, image-to-video, and video-to-video modes.
- Music generation with a selectable prompt style and Kie model ID.
- Custom model ID entry where a Kie model is enabled on the account.
- Supabase-backed credit balance and user-owned generation history.
- Background task polling while the website remains open, including while navigating between studios.
- Private Supabase Storage uploads and short-lived signed URLs for image/video source inputs.
- Flutterwave credit-package checkout and server-side payment verification.
- Responsive mobile and desktop layout.

Generation costs enforced by the Edge Function:
- Image: 3 credits
- Music: 5 credits
- Video: 8 credits

New accounts receive 50 starter credits when the generation-credit migration is installed. Credit balances are read from Supabase; they are not stored as a browser-only balance.

## Render configuration

The Render web service should use the repository root Dockerfile. Set these environment variables in the Render dashboard:

| Name | Value |
| --- | --- |
| `SUPABASE_URL` | Your Supabase project HTTPS URL |
| `SUPABASE_PUBLISHABLE_KEY` | Your Supabase publishable key (or supported anon key) |

The website reads public Supabase configuration from `/api/config`. Do not expose Supabase service-role, Kie.ai, Groq, or Flutterwave secret keys to the browser.

When the GitHub repository is connected to Render with automatic deploys enabled, commits to `main` should trigger a deployment. Check the Render dashboard for the actual deploy result; a GitHub commit alone does not prove that Render has finished deploying.

Health endpoint: `/health`

Public configuration endpoint: `/api/config`

Authenticated provider proxy: `POST /api/provider-gateway`

## Supabase setup

Apply the repository SQL migrations in timestamp order from the Supabase SQL Editor. The website relies on:
- `20261022000000_generation_history.sql` — per-user generation history.
- `20261022010000_generation_credits.sql` — starter credits and atomic credit deduction.
- `20261022030000_credit_purchases.sql` — credit purchase records and fulfilment.
- `20261022040000_novaryx_full_supabase_storage.sql` — private `user-assets` storage bucket and ownership policies.

The private `user-assets` bucket is used for source media uploads. The website requests a signed URL before passing a source file to the provider. Upload limits in the website are 35 MB; the actual bucket policy and allowed MIME types also apply.

## Provider Edge Function

Deploy `supabase/functions/provider-gateway` as the Supabase Edge Function named `provider-gateway`. Configure these secrets in Supabase Edge Function secrets:

| Secret name | Purpose |
| --- | --- |
| `KIE_API_KEY` | Image, video, and music task creation and polling |
| `FLUTTERWAVE_SECRET_KEY` | Secure payment initialization and verification |
| `FLUTTERWAVE_REDIRECT_URL` | HTTPS page URL used for payment return |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-side purchase fulfilment and administrative database operations |

The function also uses Supabase's built-in `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Never put service-role or provider secret values in GitHub source, Render public configuration, or client-side code.

After changing the Edge Function source, redeploy it from the Supabase CLI:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy provider-gateway
```

Kie.ai model identifiers and input schemas vary by model and account. The website includes common example model IDs and a custom model field; select a model actually enabled for your Kie.ai account. A task can only run if the configured provider accepts that model and its input fields.

## Android app

The Flutter Android app remains in `lib/`. The GitHub Actions workflow at `.github/workflows/build-apk.yml` builds the Android release APK. The website changes do not replace the Android application source.

## Security

- Keep Row Level Security enabled on all user-owned tables.
- Provider API secrets must remain in Supabase Edge Function secrets.
- Credit deductions and payment verification are server-side.
- Do not grant credits based on a browser redirect alone; verify the transaction with Flutterwave on the server.
- Add provider rate limits and operational monitoring before opening the service to a large public audience.
