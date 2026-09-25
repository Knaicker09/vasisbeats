# Remaining user migration: the 182 Firestore-only users

Goal: create Supabase accounts for the 182 users from the old Firestore export
(`database_export_20_09_2026.zip`) who aren't in `vms_students` yet, so they
can sign in with "email me a sign-in code" and land in the same shared
account system as the website, with no separate registration step.

**On hold (owner, 2026-09-25)** — not started, nothing below has been run.

## Pre-flight checks (done 2026-09-25)

- **Profile photos**: checked. All 119 non-null `photo_url` values in the
  export are the exact same literal placeholder
  (`https://storage.googleapis.com/vasis/default_profile.png`) — nobody in
  the old data has a real uploaded photo. Nothing to migrate here.
- **Emails**: all 299 normalize cleanly (trim + lowercase), no duplicates,
  no malformed addresses.
- **Donations**: the old `donation` field is a nested `{amount, currency}`
  map on 17 users and a flat `donation_amount` on the rest — already
  reconciled into one `(amount, currency)` pair per user in
  `migration/users_missing.csv`.
- **Practice history**: the old Firestore schema never stored any — only
  `account_type`/`donation`/`role`/`userName`/`photo_url` existed. Nothing
  to migrate beyond the account fields already captured.

## Steps

1. **Create the 182 Auth users** via the Admin API
   (`auth.admin.createUser`) — not `inviteUserByEmail` (would email
   everyone in one burst) and not a client-side `signUp` (would trigger the
   Brevo/welcome-email flow meant for organic new signups). Set
   `email_confirm: true`, no password. Send no `role` in metadata (matches
   how the app's own signup works, and avoids relying on the still-open
   trigger role-escalation hole) — everyone lands as `role='student'` by
   the trigger's default. Pass the old `userName` as `legal_name` in
   `user_metadata` so the row isn't blank.
2. **`vms_students` row**: created automatically by the existing
   `handle_new_auth_user` trigger — no manual insert.
3. **`vms_beats_access` row**: now automatic too — the new
   `trg_vms_students_beats_free_tier` trigger (added 2026-09-25) inserts a
   free-tier row the moment step 2's `vms_students` row lands. For the 8
   paid users among the 182, a follow-up upsert (same shape as
   `migration/insert_access.sql`) sets `account_type='paid'` with their old
   `donation_amount`/`donation_currency`.
4. **Verify**: row counts match (182 new `auth.users` / `vms_students` /
   `vms_beats_access`), spot-check the 8 paid users' donation amounts.

## Decisions

1. **Create all 182, or only the 8 paid?** Still open. All 182 lets everyone
   sign in immediately without re-registering; paid-only leaves ~170 dormant
   Firebase-only accounts out of the shared LMS database until those people
   register themselves.
2. **`kumar.jayanti@gmail.com`** (old admin, one of the 182): resolved
   2026-09-25 — no longer involved with the project. Don't make them admin;
   consider excluding this one email from the 182 entirely when this
   eventually runs, rather than creating a dormant account for them.
3. **Seeding `legal_name` from the old `userName` field as-is**: resolved
   2026-09-25 — approved, no validation/prettifying needed.

Blocked on decision 1 — nothing in this plan runs until the owner says go;
creating real, sign-in-capable accounts for other people isn't easily
reversible.
