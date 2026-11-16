# WatchTrack multi-user, security, and sync implementation plan

## Decisions

- Backend: Supabase (managed PostgreSQL, Supabase Auth, Edge Functions).
- Authentication: email/password, verified email, password reset.
- Existing data: preserve local data and migrate it only after an explicit, recoverable account-linking flow.
- Platforms: website, Android WebView, and iOS WKWebView share the same web application and account-backed data model.
- Priorities: security and data preservation are release blockers; cross-device sync is medium priority; the admin console is low priority.

## Current-state findings

The current application is a static HTML/CSS/JavaScript client shared by all three platforms. It stores tracking data under `watchtrack-state-v2` in browser/WebView local storage and stores a user-supplied TMDB Read Access Token under `watchtrack-tmdb-token`. The backup format contains `watchedMovies`, `tvProgress`, and `wishlist`. The website, Android assets, and iOS resources currently contain byte-identical copies of the web assets.

There is no account system or trusted server in the current app. A client-side-only implementation cannot safely hold one shared TMDB secret or enforce multi-user authorization. The current device-local state and existing export/import workflow must remain available during migration.

## Delivery sequence

### Phase 0 — safety baseline and attribution

1. Keep all work on a feature branch until checks pass.
2. Keep the current local state format readable and preserve export/import.
3. Remove repeated TMDB footer branding from content pages, but move required TMDB attribution and the approved, unmodified TMDB logo into a persistent About / Credits destination. Include the JustWatch attribution adjacent to streaming-provider information.
4. Add migration and security documentation. Do not publish a release build that implies cloud accounts are active before backend configuration and security checks are complete.

### Phase 1 — backend foundation (critical)

1. Create a Supabase project in the owner's account; configure production/staging environments separately.
2. Apply versioned SQL migrations. Use Supabase Auth as the identity provider and the verified JWT subject (`auth.uid()`) as the only source of user identity.
3. Keep application profile data separate from authorization roles. Users must never be able to grant themselves admin privileges.
4. Enable RLS on every user-owned table. Policies must scope reads, inserts, updates, and deletes to `auth.uid()`. Add automated tests proving user A cannot access user B's rows.
5. Create a server-side TMDB proxy in Supabase Edge Functions. Store the TMDB API Read Access Token as a server secret; never ship it in HTML, JavaScript, Android assets, iOS resources, app configuration, logs, or client-visible database rows.
6. Validate request paths, methods, parameters, country codes, response sizes, and rate limits in the proxy. Do not create an open proxy or accept arbitrary upstream URLs.
7. Configure HTTPS-only production URLs, restrictive CORS allowlists, auth email templates, redirect allowlists, session expiry/refresh policy, and secret rotation.

### Phase 2 — account experience (critical)

1. Add sign-up, sign-in, sign-out, email verification, password reset, and session restoration.
2. Use accessible loading, validation, error, and rate-limit states. Avoid leaking whether an email address has an account.
3. Do not put passwords, access tokens, refresh tokens, or the TMDB credential in local storage. Use the Supabase-supported session handling for the chosen platform and review WebView/native storage boundaries.
4. Keep browsing and public catalogue discovery usable where appropriate, but require authentication before accessing a personal library or syncing private data.

### Phase 3 — safe data migration and synchronization (critical/medium)

1. On first sign-in, detect local legacy state without changing or deleting it.
2. Offer an explicit import preview showing movie, TV-show, episode, and wishlist counts.
3. Before migration, create a local downloadable backup and a server-side migration checkpoint. A failed migration must leave the local copy intact.
4. Merge rather than blindly replace: union movie and wishlist IDs; merge TV episode progress by show/season/episode; preserve timestamps and known runtimes; resolve duplicate timestamps deterministically.
5. Make migration idempotent with a per-user migration marker and payload checksum. Repeating a completed import must not duplicate or erase records.
6. Verify server row counts and a read-back checksum before marking migration complete.
7. Sync authenticated changes across web, Android, and iOS. Handle offline edits and concurrent writes with explicit versioning/updated-at conflict rules; never silently replace a newer cloud state with an older local snapshot.
8. Retain local export/import as a user-controlled portability and recovery feature.

### Phase 4 — security verification (release blocker)

- Threat model: account takeover, IDOR/BOLA, cross-user reads/writes, privilege escalation, XSS, CSRF where applicable, injection, open-proxy abuse, credential leakage, replay, rate-limit bypass, dependency compromise, insecure deep links, WebView bridge misuse, backup exposure, and account deletion failures.
- Automated checks: SQL/RLS policy tests for at least two users; API authorization tests; schema/input validation tests; dependency and secret scanning; static analysis; build artifact inspection for secrets; session and logout tests.
- Manual authorized testing: inspect browser storage, network traffic, WebView configuration/bridges, deep links, auth recovery, import/export abuse, and rate limits. Retest every fixed finding.
- Record findings, severity, fix, and retest evidence. Do not describe the product as completely secure; security is an ongoing process.

### Phase 5 — low-priority admin capabilities

1. Bootstrap the first admin only through a controlled owner-operated server-side procedure after identity verification and MFA enrollment.
2. Store roles in a server-controlled table inaccessible to normal authenticated clients. Never accept role claims from user-editable metadata.
3. Add an audited admin dashboard for account support and feature configuration, protected by MFA and least privilege.
4. Source-code changes remain in GitHub with protected branches, review, and CI/CD. The dashboard must not directly edit or execute application source code.

## Data model (initial)

- `profiles`: non-privileged profile fields keyed to `auth.users.id`.
- `watchtrack_state`: one versioned JSON document per user, initially preserving the current app's `watchedMovies`, `tvProgress`, and `wishlist` shape.
- `private.user_roles`: server-managed authorization roles, not readable or writable by ordinary clients.

The initial state document keeps the existing data shape intact to reduce migration risk. Normalization into separate movie, show, episode, and wishlist tables can be considered later only with a tested reversible migration.

## Release gates and open operational prerequisites

- The owner must create/configure the Supabase project and provide project URL plus publishable/anon key through approved deployment configuration. The service-role key and TMDB token must be set only as server secrets.
- Confirm whether WatchTrack is commercial or non-commercial before public release. TMDB API terms and licensing/attribution obligations must be reviewed; adding attribution does not by itself grant commercial rights.
- Complete privacy policy, terms, account deletion, data retention, backup/restore, and support contact before accepting public users.
- No live backend or production secrets are configured by this repository change. The migration SQL is a reviewed foundation, not evidence that a deployed backend is already secure.
