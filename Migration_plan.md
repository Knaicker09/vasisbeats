# Vasis Beats — Supabase Migration & Redesign

## Context

Vasis Beats is a Flutter rhythm-practice app currently backed by Firebase (Auth email-link sign-in, Firestore for two collections `users`/`admins`, Cloud Storage + a Cloud Function for a signed-URL-gated zip of practice tracks). The project has just changed hands and is being taken over; the previous developer's Firebase setup is being retired in favor of Supabase, to unify accounts and content delivery with the existing `vasisstudio.com` platform (a full course/LMS site already live on Supabase project `vasis_studio`, 393 real students, already using Cloudflare R2 for signed content storage). Alongside the backend swap, the app is getting a full functional/UI redesign per a written requirements doc covering reliability (OTP/password auth, offline-first downloads), a new Home/Practice/Learn/Profile navigation structure, "practice intelligence" (tempo, loop, beat indicator, timer, favorites), and a closing stabilization pass.

Decisions already confirmed with the project owner (not open questions):

1. Beats merges into the existing `vasis_studio` Supabase project — one account shared with the website (`auth.users` + `vms_students`), not a separate project.
2. Beats content reuses the website's existing Cloudflare R2 bucket/credentials, not a new bucket.
3. Branding matches `vasisstudio.com` as it exists today (purple `#8637e0` accent, existing logo assets, no separate brand guide).
4. This document is written for review before implementation begins.

Separately, in this same session, the previous developer's abandoned `catcher` error-reporting plugin (a broken local path dependency, `../catcher`, that doesn't exist on this machine) was already removed from the app and replaced with a plain `runZonedGuarded`/`FlutterError.onError` handler that opens a `mailto:namelestek@gmail.com` report including the signed-in user's email. That work is **done**, not part of this plan, and is unrelated to the structured operational logging described in §6 below (that's a different, Postgres-backed mechanism for a different purpose).

---

## 0. Confirmed facts grounding this plan (verified against the actual code)

- `pubspec.yaml`'s Firebase stack — `firebase_core ^3.13.1`, `firebase_auth ^5.5.4`, `cloud_firestore ^5.6.9`, `firebase_storage ^12.4.7`, `cloud_functions ^5.5.2`, `google_sign_in ^6.3.0` — are all candidates for full removal. The Dart SDK constraint (`>=2.12.0 <3.0.0`) is stale relative to the packages actually in use and must be bumped (against whatever Flutter SDK gets installed) before `supabase_flutter` is added.
- Track content is **not** read live from Firestore. The real pattern ([lib/services/playlist_repository.dart](lib/services/playlist_repository.dart), [lib/splash.dart](lib/splash.dart)): a Cloud Function ([functions/index.js](functions/index.js)) verifies a Firebase ID token and mints a 5-minute v4 signed URL for one hardcoded object, `vasis-sounds-paid.zip`; the app downloads and unzips it to `ApplicationDocumentsDirectory/vasis/`, then parses a bundled `metadata.json` (flat `{id, album, title, url, genre, category}` list, with a legacy shim at [playlist_repository.dart:50-52](lib/services/playlist_repository.dart#L50-L52) that backfills missing `category` from `genre` and defaults `genre` to `'teen_taal_slow'`). Firestore is used only for the `users`/`admins` account data, never for track content.
- Genres/taals are hardcoded in [lib/home.dart](lib/home.dart) today: Do Taal Slow/Fast, Teen Taal Slow/Fast, Changing Speeds, plus a free "Future" catch-all.
- **Existing paid-gating bug**: [lib/home.dart:153-156](lib/home.dart#L153-L156) computes `_isPaidUser` from `user.emailVerified` (a Firebase Auth flag unrelated to payment), while the Profile screen elsewhere computes paid status correctly from Firestore's `account_type`/`donation_amount`/`role`. These two are inconsistent today. The new schema's single `vms_beats_access` table (§1) fixes this by being the one source of truth, queried the same way everywhere.
- Auth today is duplicated: **two separate, slightly-diverging deep-link handlers** — one in `main.dart`'s `initDeepLinkHandler`, one in `sign_in_screen.dart` — both keying off the same `shared_preferences` value (`email_for_signin`), which is a latent race/bug source. The rebuild consolidates this into one handler (§3).
- [lib/services/auth_service.dart](lib/services/auth_service.dart) (a Google Sign-In wrapper) is registered in [lib/services/service_locator.dart:25](lib/services/service_locator.dart#L25) but has no call site anywhere else in `lib/` — dead code, to be deleted rather than migrated.
- State pattern: `get_it` singletons (`AudioHandler`, `PlaylistRepository`, `PageManager`, `AuthService`) + `ValueNotifier`s exposed by `PageManager`, with `provider`/`ChangeNotifier` used in exactly one place (`DownloadProgress` in `main.dart`). `PageManager.init(genre, category)` → `PlaylistRepository.fetchPlaylistByGenreAndCategory` is the existing hook that maps directly onto tala/practice-set in the new schema.
- [lib/services/audio_handler.dart](lib/services/audio_handler.dart) wraps a single `just_audio` `AudioPlayer` + `ConcatenatingAudioSource` via `audio_service`. No tempo/pitch control exists yet — `AudioPlayer.setSpeed()` is the natural hook for tempo controls.
- `MaterialApp` in `main.dart` currently has no `theme:` at all — there is no existing app-wide theme to preserve or migrate, only to create new.

---

## 1. Supabase schema design

**Guiding decisions:**

1. New tables live in the same project, prefixed `vms_beats_*` so they're grep-able as a unit while still joining directly against `vms_students`/`vms_courses`/`vms_classes`.
2. **Access model is dedicated, not `vms_payments`/`vms_student_enrollments`.** Those tables are shaped for the multi-level singing curriculum (`levels_covered`, `delivery_mode`, `drip_start_date`, per-course enrollment) — forcing a flat donation-gated beats product through them means inventing meaningless values on every row, and coupling beats access to any future LMS enrollment-logic change. A small dedicated table mirroring the old Firestore `account_type`/`donation` shape is both truer to the actual product and a direct migration target.
3. **"Admin" allow-list needs no new table.** `vms_students.role` already includes `'admin'`; reuse it as-is.
4. **"Continue Practice" is derived, not a stored pointer.** A separate synced "current state" row can go stale (e.g. app crash mid-session). `vms_beats_practice_sessions` is the single source of truth; "Continue Practice" = latest row by `started_at`, backed by an index.
5. **Device-local vs. Postgres split**: Postgres holds only what must be shared across devices or is server-authoritative (catalog, access rights, favorites, practice history, error log). Download queue/progress/local file state has no cross-device sync requirement and stays entirely on-device (§4).

**New tables** (sketch — column-level review, not final DDL):

```sql
create table vms_beats_talas (
  id uuid primary key default gen_random_uuid(),
  name text not null,                      -- 'Teen Taal'
  name_es text, name_pt text,
  beats_count int,                         -- e.g. 16 for Teen Taal — drives the pulse indicator
  description text,
  image_asset text,
  display_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table vms_beats_practice_sets (
  id uuid primary key default gen_random_uuid(),
  tala_id uuid not null references vms_beats_talas(id),
  title text not null,
  title_es text, title_pt text,
  tempo_label text not null check (tempo_label in ('beginner','practice','performance')),
  bpm_min int not null,
  bpm_max int not null,
  course_id uuid references vms_courses(id),   -- nullable: Learn screen "course-linked presets"
  class_id uuid references vms_classes(id),    -- nullable: finer-grained link
  is_paid boolean not null default true,
  display_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table vms_beats_tracks (
  id uuid primary key default gen_random_uuid(),
  practice_set_id uuid not null references vms_beats_practice_sets(id),
  title text not null,
  instrument text not null check (instrument in ('mrdanga','kartals','tanpura','full_mix')),
  bpm int not null,
  r2_object_key text not null,             -- e.g. 'beats/teen-taal/practice/128bpm-mrdanga.mp3'
  file_size_bytes bigint,
  duration_seconds numeric,
  checksum_sha256 text,                    -- client-side corruption detection after download
  display_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()     -- content-update-check compares this to the local manifest
);

create table vms_beats_access (
  student_id uuid primary key references vms_students(id) on delete cascade,
  account_type text not null default 'free' check (account_type in ('free','paid')),
  donation_amount numeric,
  donation_currency text check (donation_currency in ('USD','INR')),
  granted_by uuid references vms_students(id),
  updated_at timestamptz default now()
);
-- no row = free tier; avoids writing a 'free' row on every signup

create table vms_beats_favorites (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references vms_students(id) on delete cascade,
  practice_set_id uuid not null references vms_beats_practice_sets(id) on delete cascade,
  created_at timestamptz default now(),
  unique (student_id, practice_set_id)
);

create table vms_beats_practice_sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references vms_students(id) on delete cascade,
  practice_set_id uuid not null references vms_beats_practice_sets(id),
  track_id uuid references vms_beats_tracks(id),
  tempo_bpm int,
  instrument_mix jsonb,                    -- e.g. {"mrdanga":1.0,"kartals":0.6,"tanpura":0.3}
  timer_minutes int,
  loop_enabled boolean default false,
  duration_seconds int,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz default now()
);
create index on vms_beats_practice_sessions (student_id, started_at desc);

create table vms_beats_error_log (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references vms_students(id) on delete set null,  -- nullable: pre-auth failures
  category text not null check (category in ('auth','playback','download')),
  code text not null,                      -- closed vocabulary, e.g. 'otp_verify_failed'
  context jsonb,                           -- small whitelist only, see §6 — never stack traces/PII
  app_version text,
  platform text,
  created_at timestamptz default now()
);
create index on vms_beats_error_log (category, created_at desc);
```

RLS: every `student_id`-keyed table restricts `select/insert/update/delete` to the row matching `auth.uid()`; catalog tables (`talas`, `practice_sets`, `tracks`) allow public `select` — paid-gating happens at the R2 signed-URL layer, not RLS, matching the existing free "Future" genre precedent. `vms_beats_error_log` is client `insert`-only; reading it is service-role/dashboard only.

**Instrument-mix**: model as separate per-instrument files (`vms_beats_tracks.instrument`), mixed client-side via multiple simultaneous `just_audio` players with independent volume — not pre-rendered per-combination files, which would grow combinatorially and only support on/off, not continuous blending.

---

## 2. Data migration plan

**Identity (Firestore → Supabase Auth + `vms_students`)**, one-time admin/service-role script:

1. Export Firestore `users/{uid}` + `admins/{uid}` existence.
2. Normalize each email exactly the way the website does ([auth.ts](../vasis_website/src/lib/supabase/auth.ts) `normalizeEmail`: trim + lowercase) and look up `vms_students` by that email.
   - **Match** (already a website/LMS student): don't create a new `auth.users` row — link the existing `vms_students.id`, backfill `vms_beats_access` from the Firestore `account_type`/`donation`, and only set `role='admin'` if not already elevated (never downgrade an existing teacher/admin).
   - **No match**: create via Admin API `auth.admin.createUser({email, email_confirm: true})` — not `inviteUserByEmail`, which would email everyone at once during a bulk backend cutover. Insert a matching `vms_students` row and `vms_beats_access` row.
3. The old system had **no passwords** (email-link only) — don't fabricate one. First sign-in post-migration is always via OTP; the person can set a password afterward via "forgot password" if they want one.
4. Keep an idempotent `firebase_uid → student_id` mapping (temporary migration-only table) so the script is safely re-runnable and support tickets are traceable.
5. Dry-run against a Supabase branch first, diff row counts, then apply to production.

**Content migration** (zip/JSON → R2 + Postgres):

1. Unzip `vasis-sounds-paid.zip`, parse `metadata.json`, applying the same legacy `category`/`genre` shim already in `playlist_repository.dart` so nothing is silently dropped.
2. Group the flat track list by inferred tala/tempo-band (from the existing `genre` naming, e.g. `teen_taal_slow`) to seed `vms_beats_talas` and `vms_beats_practice_sets`.
3. Upload each file to the **existing** website R2 bucket under a new prefix (e.g. `beats/<tala-slug>/<practice-set-slug>/<track-id>.mp3`), isolated from LMS content by prefix, using the same credentials already in the website's `.env`.
4. Compute and store `checksum_sha256`/`file_size_bytes` per track during upload.
5. Keep the old Firebase project + Cloud Function read-only for one release as a fallback before deleting anything.

---

## 3. Auth flow (Flutter, `supabase_flutter`)

Add `supabase_flutter`. Remove `firebase_auth`, `cloud_firestore`, `firebase_storage`, `cloud_functions`, `google_sign_in`, `firebase_core`, `lib/firebase_options.dart`, the `functions/` directory, and the dead `lib/services/auth_service.dart`. Nothing in the requirements needs Firebase Cloud Messaging or any other Firebase service, so this is a full, clean removal.

| Requirement                                          | Supabase Dart call                                                                                                                                                                                                                                                                                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| OTP + link sign-in                                   | `supabase.auth.signInWithOtp(email:, emailRedirectTo:)` — sends code + magic link in one email; replaces both existing deep-link handlers with **one** consolidated listener (`app_links` + `supabase.auth.getSessionFromUrl()`)                                                                                                           |
| Enter code manually                                  | `supabase.auth.verifyOTP(email:, token:, type: OtpType.email)`                                                                                                                                                                                                                                                                             |
| Password + forgot password                           | `signInWithPassword`, `resetPasswordForEmail`, `updateUser(UserAttributes(password:))`                                                                                                                                                                                                                                                     |
| Resend code/email                                    | `supabase.auth.resend(type: OtpType.signup, email:)`                                                                                                                                                                                                                                                                                       |
| Use another email                                    | UI-only — clear the stored email, restart the flow                                                                                                                                                                                                                                                                                         |
| Contact support                                      | `mailto:` via `url_launcher`, reusing the pattern already in `sign_in_screen.dart`'s donation-email link                                                                                                                                                                                                                                   |
| Persistent session, survives restart & works offline | `supabase_flutter` auto-persists the session to platform secure storage and rehydrates `currentSession` synchronously before any network call. If a JWT refresh fails while offline, treat the still-unexpired local session as authenticated and let refresh happen lazily on the next successful network call — don't block the UI on it |
| Init                                                 | `Supabase.initialize(url:, anonKey:, authOptions: FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce))` in `main()`, replacing `Firebase.initializeApp()`                                                                                                                                                                            |

---

## 4. Download manager & offline system (Flutter-side)

- **HTTP**: add `dio` (not plain `http`) — built-in `Range`/resume, cancel tokens, and progress callbacks, directly serving "retry/resume." `path_provider` (already a dependency) stays the file-storage root, same `ApplicationDocumentsDirectory/vasis/` convention.
- **Local metadata**: `sqflite`, not `Hive`/`shared_preferences` — the data is relational-shaped (query "all tracks for this practice set" / "all currently downloading"), which a flat key-value store handles awkwardly, and needs no extra native codegen the way `Hive` does. Device-local table (independent of the Postgres shape):

```
local table download_manifest (
  track_id text primary key,       -- matches vms_beats_tracks.id
  practice_set_id text,
  local_path text,
  expected_checksum text,
  bytes_total integer,
  bytes_downloaded integer,
  status text,                     -- 'queued'|'downloading'|'complete'|'failed'|'stale'
  retry_count integer default 0,
  server_updated_at text,          -- snapshot for the update-check diff
  downloaded_at text
)
```

- **Corruption detection**: after download, SHA-256 the local file and compare to `expected_checksum`; mismatch → `status='failed'`, delete the partial file, surface a retry action. On app start, re-verify file size for anything marked `complete` before trusting it as playable — catches partial writes from a crashed app.
- **Update-check**: on foreground/Home load (network permitting), diff `vms_beats_tracks.updated_at`/`checksum_sha256` against `download_manifest.server_updated_at` for downloaded sets; mismatches get flagged `stale` (an "update available" badge) rather than auto-redownloaded, respecting the user's storage/data choice.
- **Offline-first list architecture**: a new `DownloadManager` service in `get_it` (parallel to the existing `PlaylistRepository`/`AudioHandler` singletons), backed by a `ValueNotifier<List<LocalTrack>>` populated synchronously from `sqflite` on init — Home/Practice screens bind to that first; a separate background call refreshes the Postgres catalog and merges in newly-available items. This extends the existing `PageManager` `ValueNotifier`-per-concern pattern rather than introducing a new one.
- **Retry/resume**: `dio`'s `Range` support plus the manifest's `bytes_downloaded` drives resume; capped exponential backoff (3 attempts), with `retry_count` persisted so a killed app doesn't silently reset it.

---

## 5. UI/navigation redesign

New `MainShell` (net-new) owns the bottom nav, replacing `main.dart`'s current direct `EmailLinkSignInScreen`/`ProfileScreen` `FutureBuilder` routing.

| Tab      | Screen                                                                                                                                                                                                                                 | Fate of existing files                                                                                                                                                                                                                                                                                                                                                                                                                          |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Home     | `lib/screens/home_screen.dart` (net-new) — Start Practice CTA, Continue Practice card (latest `vms_beats_practice_sessions` row), recent/favorites, offline status                                                                     | Replaces `lib/home.dart`'s grid-of-taals `HomeScreen`; that grid becomes a "browse talas" section reachable from Practice                                                                                                                                                                                                                                                                                                                       |
| Practice | `lib/screens/practice_screen.dart` (net-new, absorbs `lib/screens/beat_screens.dart`'s `BeatScreen`)                                                                                                                                   | `beat_screens.dart`'s category-tab/playlist-loading logic (`_initGenreData`, `PageManager.init`) is reused almost as-is — genre/category maps directly to tala/practice_set. New on top: BPM display + tempo slider (wraps `setSpeed`), instrument-mix panel, timer picker, loop toggle (extends existing `RepeatButton`/`RepeatButtonNotifier`), animated beat/pulse indicator (`AnimationController` synced to `vms_beats_talas.beats_count`) |
| Learn    | `lib/screens/learn_screen.dart` (net-new) — short tutorials (bundled markdown/JSON is enough for v1, no table needed for fixed content) + course-linked presets via `vms_beats_practice_sets.course_id`/`class_id`                     |
| Profile  | Repurpose `sign_in_screen.dart`'s `ProfileScreen` — same card layout, swap Firebase/Firestore calls for Supabase, add downloaded-content management (from `DownloadManager`) and practice history (from `vms_beats_practice_sessions`) |

- `EmailLinkSignInScreen` (in `sign_in_screen.dart`): kept as the pre-auth screen, rewritten internally for Supabase OTP/password, with the required recovery controls (resend, manual code entry, another email, contact support) as explicit visible buttons rather than the current macOS-only paste fallback.
- `admin_screen.dart`: kept, rewritten to read/write `vms_beats_access` (+ optionally `vms_students.role`) via Supabase instead of the Firestore `StreamBuilder`.
- `splash.dart`: today it downloads the zip, checks `metadata.json`, and handles deep links — those responsibilities move to `DownloadManager` (§4) and the consolidated auth handler (§3); `splash.dart` becomes a thin branding/loading screen only.
- Branding: new `lib/theme.dart` defining a `ColorScheme` seeded from `#8637e0`, applied via `MaterialApp(theme:)` — there is currently no theme at all to preserve. Accessibility pass: pair every color-only status indicator (e.g. `sign_in_screen.dart`'s red/green account-type text) with an icon/label, check contrast where text overlays `images/vasis.jpeg`, respect `MediaQuery.textScaler`.
- Reuse as-is: `audio_video_progress_bar` (seek bar), `just_audio`/`audio_service` (playback engine), `PageManager`/`ValueNotifier` pattern.

---

Now for phase 6 and also remove old and obsolete files and give me a list of things to be done / added after all the phases are done.
## 6. Error/failure logging Remove old and obsolete files. Give a list of things that need to be done / added.

Distinct from the mailto crash-reporter already wired up (uncaught exceptions → developer inbox). This is structured operational logging of **expected** failure categories (auth/playback/download) for pattern diagnosis, written to the `vms_beats_error_log` table from §1 rather than a client-only log — the stated goal ("diagnosing recurring issues") needs cross-user aggregation a per-device log can't give, and the table is cheap and dashboard-queryable at this app's scale.

"Privacy-respectful" concretely means:

- No raw stack traces or free-text exception messages — only a closed-vocabulary `code` (`otp_verify_failed`, `otp_expired`, `session_refresh_failed`, `playback_source_error`, `playback_stall_timeout`, `download_checksum_mismatch`, `download_network_failure`, `download_disk_full`, …).
- `context jsonb` is a whitelist (e.g. `{track_id, http_status, attempt_number}`), never file paths, device identifiers, or IP.
- `student_id` nullable and only populated when authenticated at failure time — pre-auth OTP failures still get logged, without identity.
- No email/name ever duplicated into `context` — support follow-up joins on `student_id` instead.
- Client can only `insert` its own rows; reading the log is service-role/dashboard only.

---

## 7. Phase sequencing

1. **Schema & backend foundation** — create the `vms_beats_*` tables and RLS policies (§1), validated on a Supabase branch first. Nothing else can be built or tested against real data without this.
2. **Identity & content migration** — run the Firestore→Supabase identity migration and the zip→R2/Postgres content migration (§2), dry-run on a branch, then applied to production. Produces a fully populated project the rest of the work builds against from day one instead of fake data.
3. **Auth rebuild** — `supabase_flutter` swap-in end-to-end (§3): sign-in rewrite, consolidated deep-link handler, password/forgot-password, session persistence, visible recovery controls. Remove the Firebase auth packages. Validated against real migrated accounts.
4. **Download manager & offline system** (§4) — depends on Phase 3 (needs a session to request signed R2 URLs) and Phases 1–2 (needs real `vms_beats_tracks` rows and R2 objects).
5. **Core redesign & practice intelligence** (§5) — the largest UI phase; depends on 3+4 being solid (a meaningful Practice screen needs both auth and downloaded content) and on Phase 1's favorites/session tables. Branding/accessibility pass happens once at the end of this phase, across all new screens together.
6. **Error/operational logging** (§6) — wired into the auth/playback/download code paths built in Phases 3–5; sequenced last among functional work since it instruments flows that must already exist, but lands before Phase 7 so stabilization has real diagnostic data to check against.
7. **Tests & stabilization** — explicit closing phase. Deliberately exercise every loading/success/empty/error state (force airplane mode, a corrupted download, an expired session — not just happy paths), verify the migration's dual-account-linking edge case (a person who is both an existing LMS student and a new beats signup) lands as one account, and confirm Phase 6's log is capturing the right categories. Also the point to revisit the `pubspec.yaml` SDK-constraint bump flagged in §0 if not already forced earlier by `supabase_flutter`'s own constraints.

**First milestone**: Phases 1–3 — a user can sign in with their real, migrated account and see correct paid/free status, even before any beats play. Phases 4–5 are the second milestone (actual practice functionality). Phase 6 rides along inside 3–5 rather than gating anything. Phase 7 is continuous but reported as a distinct closing effort.

---

## Critical files

- [lib/services/playlist_repository.dart](lib/services/playlist_repository.dart) — current content-loading logic to replace with Postgres/R2 calls
- [lib/services/service_locator.dart](lib/services/service_locator.dart) — `get_it` registrations; add `DownloadManager`, remove `AuthService`
- [lib/page_manager.dart](lib/page_manager.dart) — existing genre/category state pattern to extend for tala/practice-set
- [lib/screens/sign_in_screen.dart](lib/screens/sign_in_screen.dart) — auth screen + Profile screen, rewritten for Supabase
- [lib/main.dart](lib/main.dart) — app entry, `Supabase.initialize`, consolidated deep-link handler, theme
- [lib/home.dart](lib/home.dart) — current paid-gating bug and taal grid, superseded by Home/Practice screens
- [functions/index.js](functions/index.js) — Cloud Function to retire once the R2 signed-URL path is live
- [pubspec.yaml](pubspec.yaml) — dependency swap (Firebase → `supabase_flutter`, `dio`, `sqflite`) and SDK constraint bump

## Verification

- **Schema**: apply each phase's migrations to a Supabase branch first (`create_branch` → `apply_migration` → `list_tables`/`describe_table_schema` to confirm shape) before merging to `vasis_studio` production, given it holds live data for 393 real students.
- **Migration script**: dry-run against the branch, diff row counts against the Firestore export and against `vms_students`' existing 393 rows to confirm no accidental duplicate-account creation for people who are both LMS students and beats users.
- **Auth**: once Flutter is installed and `flutter pub get` succeeds, manually exercise OTP sign-in, manual code entry, password reset, "use another email," and a forced-offline app restart (session should still show signed-in).
- **Downloads**: test on a real device/emulator — kill network mid-download (resume should pick up), corrupt a downloaded file on disk (should be detected and offer retry), and modify a track's `updated_at` in Supabase to confirm the "update available" badge appears.
- **UI**: run the app and walk all four tabs plus every explicitly-required state (loading/success/empty/error) per screen, since this can't be verified by type-checking alone.
- **Closing**: query `vms_beats_error_log` after a stabilization pass to confirm real failures are landing with the expected `code` values and no PII leakage in `context`.
