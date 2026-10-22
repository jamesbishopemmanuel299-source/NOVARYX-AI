# NOVARYX-AI

Flutter Android app for AI chat (Groq), image/music/video generation (Kie.ai), Supabase authentication, and a server-side Flutterwave payment gateway.

## Features
- Groq chat requests routed through a Supabase Edge Function.
- Kie.ai image, music, and video task creation/status polling routed through the same Edge Function.
- Flutterwave payment initialization and transaction verification endpoints in the Edge Function.
- Supabase email/password authentication.
- Provider API secrets stay on the server in Supabase Edge Function secrets, not inside the APK.
- GitHub Actions ARM64 release APK workflow.

## Configure provider secrets in Supabase

1. Open your project at https://supabase.com/dashboard.
2. Select **Edge Functions** → **Secrets** (or **Project Settings → Edge Functions → Secrets**, depending on dashboard layout).
3. Add these secrets with the exact names below. Enter each real key privately in the Supabase dashboard; do not put the values in GitHub source files or this README.

| Secret name | Value |
| --- | --- |
| `GROQ_API_KEY` | Your Groq API key |
| `KIE_API_KEY` | Your Kie.ai API key |
| `FLUTTERWAVE_SECRET_KEY` | Your Flutterwave secret key |

The function uses Supabase's built-in `SUPABASE_URL` and `SUPABASE_ANON_KEY` environment values. Do not use a Supabase service-role key in the Flutter app.

## Deploy the Edge Function

Install and sign in to the Supabase CLI, then run these commands from the repository root:

```bash
supabase login
supabase link --project-ref vihbsfrwnslnmheowkhy
supabase functions deploy provider-gateway
```

The function requires a valid signed-in Supabase user. In the app, create an account or sign in from **Settings** before using chat or generation. The function checks the user's session and reads provider secrets server-side.

## Flutterwave actions

The deployed `provider-gateway` function supports:
- `flutterwave-initialize`: expects `email`, `amount`, and `redirect_url`; optional `name`, `currency`, and `tx_ref`.
- `flutterwave-verify`: expects `transaction_id`.

These are secure server-side endpoints; a Flutterwave checkout/payment screen has not yet been added to the app UI. Always verify a transaction on the server before granting credits, subscriptions, or access.

## Build an APK

1. Add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` as GitHub Actions repository secrets if you want the build to use your project values.
2. Open **Actions** → **Build Small Android APK** and run the workflow, or push a commit to `main`.
3. Download the `novaryx-arm64-release-apk` artifact from a successful run.

For local development with Flutter installed:

```bash
flutter pub get
flutter run
```

## Security notes
- Never expose Groq, Kie.ai, or Flutterwave secret keys in Flutter source, GitHub commits, or the built APK.
- Supabase Edge Function secrets are server-side configuration; the app does not download or reveal them.
- Keep Row Level Security (RLS) enabled on any tables containing user data.
- Add usage limits/rate limits before publicly releasing provider-backed AI features.
- The current Flutterwave endpoints provide payment initialization and verification, but do not by themselves add a payment UI or automatic crediting.

## Current limitations
- Kie.ai model IDs and input fields vary. The app sends a common prompt-based task input; some models may require additional fields.
- Results depend on the provider returning a task ID and result URL in its response.
