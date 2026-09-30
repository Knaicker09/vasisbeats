# Vasis Beats

Flutter rhythm-practice app, migrated from Firebase to the existing Supabase project `vasis_studio` (ref `bzytabulixdmoxxalnuf`), shared with vasisstudio.com. Full plan and history: `C:\Users\NamelesTek\.claude\plans\melodic-finding-gray.md` and `Migration_plan.md`.

## Status

Phases 1, 3, 4, 5, 6 done. Phase 2 (data migration) and Phase 7 (testing) outstanding — see below.

Since the last review: tier gating (client + server), the rest of Phase 4 (stale detection, retry UI, progress, per-set/course downloads, offline indicator, catch-up on reconnect), per-user/per-set playback settings persistence, website-parity auth, a dark neon retheme (2026-09-30, see "Visual design"), and Windows/Linux support (sqflite FFI, no audio_service) are all built. The web target is online-only.

## Outstanding work (owner's notes)

1. **Register the app with Supabase so email links don't always open the website.** Auth emails currently redirect to the site URL (vasisstudio.com). The app needs its own redirect URL/deep link configured in the Supabase dashboard, plus native config (Android intent-filters, iOS/macOS associated domains). Also make sure the **Confirm signup, Magic Link and Recovery** email templates include `{{ .Token }}` — the app uses typed 6-digit codes for sign-up confirmation, code sign-in and password reset.
2. **Add the env variables when the app is published.** `.env` (gitignored, declared as a pubspec asset) must hold `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Because it is a bundled asset, a build fails if `.env` is missing — release/CI builds must create it first.
3. **Test thoroughly, and fix whatever turns up.** Only the web build has been compiled and rendered (login screen checked visually). Nothing has run on Windows/macOS/iOS/Android. Cover: sign-up/OTP/password/reset, cross-login with a website-created account (and the reverse), offline restart while signed in, download resume/corruption recovery, multi-stem sync, background/lock-screen playback, tier gating with a free and a paid account, and the loading/empty/error state of every screen. No automated tests exist.
4. **Tracks: done 2026-09-25.** All 91 files uploaded to the shared R2 bucket (`kn-09-p4-vasis-e-learning`) under a new `beats/<tala-slug>/<speed-mix-slug>/<file>` prefix (e.g. `beats/teen-taal/slow-kartal/k90.mp3`), verified by size against the live objects. 3 talas (Teen Taal beats_count=16; Do Taal and Changing Speeds beats_count left null — unknown, see below), 11 practice sets and all 91 tracks inserted into `vms_beats_talas`/`vms_beats_practice_sets`/`vms_beats_tracks` with real `r2_object_key`/`file_size_bytes`/`duration_seconds`/`checksum_sha256`. `is_paid` follows the tier rule (Teen Taal Slow free, everything else paid — 34 free tracks, 8 paid sets). Source data, generated SQL and the full mapping are kept in `migration/` (gitignored): `tracks_manifest.json`, `insert_catalog.sql`.
   **Placeholders that need the owner's real values** (flagged, not silently guessed): `tempo_label` was assigned mechanically (slow→beginner, fast→practice, changing-speeds→performance) — adjust if a different tier scheme is wanted. The 2 Changing Speeds tracks have no per-file BPM in the source data, so they were inserted with `bpm=100`, `bpm_min=60`, `bpm_max=200` as a placeholder (`vms_beats_tracks.title like 'Kartal & Mridanga 3 Speed%'`). Do Taal's `beats_count` is still null (unconfirmed).
   **Other findings from the source zip** (`vasis-sounds-paid.zip`, gitignored): 447 MB, all 160 kbps, no corruption/duplicates. The files are pre-mixed (K / KM / KMT "tehai"), not stems — the instrument mixer has nothing to mix. `TFKM100.mp3` was missing from the old `metadata.json` but is included here anyway. Id 79 (probably `DSKM180`) was missing from the old manifest and the zip — not included. Loudness differs up to ~9 dB between series (not fixed).
   **Player fixed for this catalog shape (2026-09-25).** `PracticeController` used to pick one track per `instrument` key with no regard for BPM, so a set with several BPM-variant tracks of the same instrument (every set in the real catalog) silently dropped all but one arbitrary file — and worse, the loaded audio didn't even match the BPM used for the speed-ratio math, so the tempo slider's number and what was actually playing could disagree. Now `PracticeController` keeps every downloaded track per instrument sorted by BPM and always plays the one nearest the requested tempo, swapping to a closer real recording (debounced, so a slider drag stays smooth) rather than time-stretching one file across the whole range. See `practice_controller.dart` (`_tracksByInstrument`, `_nearestTrack`, `_swapToNearestTracks`) and `practice_audio_handler.dart` (`swapStemSource`). `flutter analyze lib`: still clean, no new issues.
5. **Migrate users: 117 of 299 done 2026-09-25, 182 deferred by owner.** Firestore export (`database_export_20_09_2026.zip`, LevelDB format, gitignored) analysed: 299 users + 2 admin entries. The 117 that already exist in Supabase (matched by lowercased email) got a `vms_beats_access` row upserted from their old `account_type`/`donation` (11 paid, 106 free — free rows store `donation_amount = null`, not 0). Every other existing student (278 more, never in the old Firebase app) was also backfilled with a free-tier row the same day — all 395 current `vms_students` now have an access row. The 182 missing users (174 free, 8 paid, none of them yet in `auth.users`/`vms_students`) are **not created yet** — owner will do that later; the concrete plan (steps, pre-flight checks incl. old profile photos — nothing real to migrate there — and open decisions) is written up in `migration/PLAN_remaining_users.md`. `kumar.jayanti@gmail.com` (old admin list) is among the missing 182. Lists in `migration/users_missing.csv` / `users_existing.csv` (gitignored, contain emails); generated SQL in `migration/insert_access.sql`.
   **New: auto free-tier provisioning (2026-09-25).** Migration `beats_auto_free_tier_on_new_student` added a trigger, `trg_vms_students_beats_free_tier` (`AFTER INSERT ON vms_students`), that inserts an explicit `vms_beats_access` row with `account_type='free'` for every new student — whether the account originates from a website signup or a beats-app signup (both ultimately insert into `vms_students`, which this trigger watches). `on conflict (student_id) do nothing`, so it's safe alongside any path that later sets access explicitly (e.g. an admin marking someone paid). No manual step needed going forward.
6. **Readme Updation** Update the readme file to reflect uptodate stack and repo info.

## Other known items

- **Security (shared DB):** the `handle_new_auth_user` trigger trusts a client-supplied `role` in signup metadata, so anyone can create an account as `admin`/`teacher`. The app never sends `role`, but the website endpoint and raw API calls can. Fix the trigger to ignore client `role` (needs the owner's call since it affects the website too).
- Website `/api/files/read` (used for downloads and web streaming) has no auth check — paid content is not actually access-controlled at the file layer, only hidden at the catalog layer.
- **Security (website, shared R2 bucket):** `/api/files/upload` (presigned PUT for any key/folder) and `/api/files/delete` (deletes any key) also have no auth, and `middleware.ts` doesn't cover `/api/*`. Anyone can upload to or delete from the bucket that holds the LMS content and, after seeding, the beats tracks. Add an admin check (or the webhook-secret approach `delete-by-trigger` uses). Don't use the upload route for seeding beats; use the S3 API credentials directly.
- Old Firebase `getSignedUrl` Cloud Function is still deployed; shut it down after migration.
- App identity is still the tutorial's: package id `dev.suragch.flutter_audio_service_demo`, project name `flutter_audio_service_demo`, "Rate the app" store links point at the previous developer's listings. `flutter_icons` still points at `images/appicon.png`. Android release builds fall back to debug signing without `key.properties`. iOS/macOS associated domains and keychain groups still use the old demo identifiers.
- Profile photo upload was removed with Firebase Storage; needs an R2-backed replacement.
- Learn-screen tutorial text is placeholder wording.
- UI is English-only (the schema has `_es`/`_pt` columns, unused). Tala names are shown in English: `OfflineCacheService` maps "Teen Taal" → "Three Beats" and "Do Taal" → "Two Beats" in tala names and practice-set titles on read (`_talaNamesInEnglish`); the database keeps the original names.
- Deep links and Google/Apple sign-in are not built (the website has Google disabled).
- Welcome email and Brevo contact sync call the production vasisstudio.com endpoints, so test accounts created in dev also hit them.
- `vasis_website.zip` (gitignored) contains live secrets in its `.env.local`; delete when no longer needed.
- Windows builds need Developer Mode enabled (plugin symlinks): `start ms-settings:developers`. Android SDK not installed.

## Auth: deviations from the website

Same normalisation, signup metadata keys, `verifyOtp type:'email'`, resend `type:'signup'`, Brevo sync and validation strings, so accounts work on both. Deliberate differences:
- No `role` is sent on signup.
- `password_hash` is stored as `'app'`, not the plaintext password the website stores.
- Code sign-in uses `shouldCreateUser: false` (existing accounts only), so typing a stray email doesn't create an LMS student.
- Password reset is an emailed 6-digit code, not a link.
- The website's "complete profile" step is not replicated.
- Shorter registration form (2026-09-30): first + last name only, saved together as `legal_name`; `initiated_name` (spiritual name) blank; no phone number, so `phone_number`/`country` are not sent and `currency` is `'USD'` (the website's fallback); `preferred_language` is always `'en'`, with no picker. Brevo sync no longer sends `whatsapp`/`location`, so the website's duplicate-number conflict can't block an app signup.
- The app is English-only regardless of an account's `preferred_language` (existing website accounts with `es`/`pt` still see English).

## Platform behaviour

- `lib/platform_support.dart` is the switch: `offlineSupported = !kIsWeb`.
- **Web:** online-only. Live Supabase reads, streaming from `https://www.vasisstudio.com/api/files/read?key=`; no SQLite, downloads, encryption, or offline UI.
- **Windows/Linux:** SQLite via `sqflite_common_ffi` (`db_bootstrap_native.dart`); playback works without `audio_service` (no lock-screen controls).
- **Android/iOS/macOS:** full feature set incl. background playback via `audio_service`.

## Track downloads

No per-track/per-set download controls. `DownloadManager.syncAll()` downloads every active track the user can access in the background; it is started by every successful `OfflineCacheService.refreshAll` (on each sign-in/app start from `MainShell`, pull-to-refresh, reconnect). Tracks still failing after the automatic retry cap show as a "Some tracks did not download → Try again" tile on Home (`syncAll(userInitiated: true)`). Progress/counts come from `DownloadManager.status`. Profile shows a read-only storage summary.

## Visual design

Dark-only neon theme (owner's choice, 2026-09-30, modelled on the "rythm" app and a beat-pad app): deep indigo background with a faint grid and slowly drifting glows, cyan (primary) and violet (secondary) neon rims with glow, blue→violet gradient CTAs, pink/amber/green accents. Sora (bundled, `assets/fonts/Sora.ttf`) for headings/labels/numbers, Nunito for body. Applies to auth screens too, so the app no longer looks like vasisstudio.com. The Vasis Studio logo has navy lettering that vanishes on dark, so `BrandMark` (gradient waveform badge + "Vasis Beats" wordmark) replaces it in the UI; the app icon is unchanged. Practice player is a pad console: beat lights (sam in pink), LOOP / PLAY / TIMER pads (timer opens a bottom sheet), BPM stepper (tap ±1, long-press ±5) + slider, mix strip. Motion (background drift, play-pad breathing) stops under the OS reduce-motion setting. Put glow shadows only behind opaque fills — translucent fills let the glow wash the panel out.

## Tier gating

Entitled = admin OR `account_type = 'paid'` OR `donation_amount > 0` (`private.vms_beats_caller_is_paid()`, surfaced to the app as `is_paid` by `beats_get_my_profile`). Enforced in the client (locked sets, no downloads) and by RLS on `vms_beats_tracks`.

## Working with the owner

- If asked what's left, remind them of the outstanding-work list above.
- Check in occasionally on those items rather than letting them go stale.
- Don't pad finished-work summaries with routine "coming soon" notes.

## Code map

- `lib/main.dart` — init, error reporting (mailto to namelestek@gmail.com), auth-driven routing, sign-out cache cleanup.
- `lib/platform_support.dart` — platform capability flags.
- `lib/ui/` — `brand.dart` (neon design tokens, `nunito()`/`sora()` text helpers, `AppTheme.dark`), `widgets.dart` (`NeonBackground`, `GlassTile`, `PortalCard`, `NeonPad`, `GradientButton`, `BrandMark`, …), `dialogs.dart`.
- `lib/screens/` — `main_shell` (nav), `home_screen`, `practice_screen`, `learn_screen`, `profile_screen`, `admin_screen`; `auth/` holds login, register, forgot/change password and the OTP view.
- `lib/services/` — `auth_service`, `welcome_email`, `beats_profile_service`, `offline_cache_service` + `local_database` (+ `db_bootstrap*` conditional import), `download_manager` + `track_encryption_service`, `practice_audio_handler` + `practice_controller` + `practice_settings_service` (multi-stem player and saved settings), `connectivity_service`, `error_log_service`, `service_locator`.
- `vms_students` rows are created by a database trigger on `auth.users`; the app never inserts them.
