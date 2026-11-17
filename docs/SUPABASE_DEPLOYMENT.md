# Supabase deployment runbook

Project reference: `yoibqnoimcownxtuczbe`

Project URL and client publishable key are supplied in `web/supabase-config.js`. The publishable key is intended for client use; never place the service-role key or TMDB Read Access Token in that file or any frontend/native asset.

## 1. Install and link the Supabase CLI

Install the Supabase CLI using its official instructions, then authenticate:

```bash
supabase login
supabase link --project-ref yoibqnoimcownxtuczbe
```

Review the SQL migrations before applying them. Then deploy:

```bash
supabase db push
supabase functions deploy tmdb-proxy
```

Do not run migrations against production until the project has a current backup and the migration has been reviewed in the Supabase SQL editor or a staging project.

## 2. Configure server secrets

Set the TMDB API Read Access Token only as a Supabase Edge Function secret. The Supabase project URL, publishable/anon key, and service-role key are supplied by the Supabase runtime; never copy the service-role key into client configuration.

```bash
supabase secrets set TMDB_API_READ_ACCESS_TOKEN="YOUR_TMDB_API_READ_ACCESS_TOKEN"
supabase secrets set WATCHTRACK_ALLOWED_ORIGINS="https://watchtrack.local,http://127.0.0.1:8765,https://YOUR_PRODUCTION_DOMAIN"
```

Replace the production-domain placeholder with the exact HTTPS origin used by the deployed website. Keep only origins that are actually used. The Android app's local origin is `https://watchtrack.local`; the current iOS local server origin is `http://127.0.0.1:8765`. Confirm the latter is reachable as an allowed CORS origin in the chosen Supabase deployment configuration before enabling the proxy in iOS.

## 3. Configure Supabase Auth

In Supabase Dashboard → Authentication → URL Configuration:

- Set the production Site URL to the canonical WatchTrack website origin.
- Add the production profile URL and local development profile URLs to the redirect allowlist.
- Enable email/password sign-up and email confirmation.
- Configure SMTP for reliable production verification and password-reset delivery.
- Use a custom email domain and SPF/DKIM/DMARC records before public launch.

The current account UI redirects to `/profile.html` after email verification or password recovery. Update the allowlist to match the exact deployment origin.

## 4. Verify database isolation before release

Create two test accounts. Confirm account A cannot select, update, or delete account B's `watchtrack_state` row, even if account A manually supplies B's UUID. Confirm anonymous requests cannot access profile or state tables. Confirm normal authenticated users cannot access `private.user_roles` or grant themselves a role.

Test registration, email verification, login, logout, password reset, and session expiry. Verify the Edge Function rejects missing/invalid JWTs, unsupported TMDB paths, unexpected query keys, disallowed browser origins, and rate-limit overflow.

## 5. Important current limitations

- The frontend account client currently uses the Supabase JavaScript SDK's default persisted browser session storage. This is a development integration, not the final hardened session architecture. Before public release, implement HttpOnly/Secure/SameSite cookie sessions for the website and native secure credential storage for Android/iOS, or document and accept a reviewed alternative after a threat assessment.
- The new account UI is currently on the profile page. Cross-page session restoration is loaded on home, discover, and profile.
- Local-to-cloud migration is explicit and downloads a backup first. Cloud sync is gated on successful migration. Conflict checks use the server revision; a conflict pauses sync rather than overwriting the cloud row.
- TMDB requests still use the legacy per-device token until the app's TMDB client is switched to the authenticated Edge Function. Do not remove the legacy token UI before the proxy integration is tested end-to-end.
- These migrations and functions have not been deployed or tested against the live project by this repository change. Do not invite public users yet.
