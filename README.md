# NOVARYX-AI

Flutter Android starter for AI chat (Groq) and image, music, and video generation (Kie.ai).

## Features
- Chat screen using Groq's OpenAI-compatible chat completions API.
- Image, music, and video generation screens using Kie.ai task creation and status polling.
- Settings screen for provider keys and model IDs.
- Optional Supabase connection and email/password sign-up, sign-in, and sign-out.
- Provider secrets are entered on-device and stored with Android secure storage; they are not committed to this repository.
- GitHub Actions workflow to build a debug APK.

## Build an APK
1. Open this repository in GitHub.
2. Go to **Actions** and run **Build Android APK**, or push a commit to trigger it.
3. Download the `novaryx-debug-apk` artifact from the completed workflow run.

For local development with Flutter installed:
```bash
flutter create . --platforms=android
flutter pub get
flutter run
```

## Configure Supabase
1. Create a project at https://supabase.com/dashboard.
2. In Project Settings → API, copy the Project URL and the publishable/anon key (never use the service-role key in a mobile app).
3. Open NOVARYX-AI Settings, paste both values, tap **Connect Supabase**, then use the email/password controls to create an account or sign in.
4. If email confirmation is enabled, confirm the email before signing in.

This adds Supabase Authentication. Chat-history cloud sync and database tables are not enabled by this change; configure database policies before storing private user data.

## Configure providers
Open the app's **Settings** page and enter:
- Groq API key and chat model (default model ID: `llama-3.3-70b-versatile`).
- Kie.ai API key.
- Kie.ai model IDs for image, music, and video. Kie model IDs and input fields can change, so use model IDs and parameters supported by your Kie.ai account.

## Important security note
This starter calls provider APIs from the device. Secure storage is safer than hardcoding secrets, but a client app cannot fully protect a provider key from a determined reverse engineer. For a public release, put provider keys behind your own authenticated backend and rate limits. Never commit real keys to GitHub.

## Current limitations
- Kie.ai models have different input requirements. The app sends a common prompt-based task input; some models may require additional fields or a different model ID.
- Generated results depend on the provider returning a task ID and a result URL in its status response.
- This repository contains the Flutter source and CI workflow; the first GitHub Actions build generates the native Android scaffold.
