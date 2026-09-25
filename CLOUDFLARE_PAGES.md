# Deploying the web build to Cloudflare Pages

The Vasis Beats web target (`flutter build web`) is a static, online-only
build — see `lib/platform_support.dart`. This replaces the old Next.js
vasisstudio.com site, which has been removed.

## Cloudflare Pages dashboard setup (Git integration)

1. Create a Pages project, connect it to this repo, and point it at this
   branch.
2. Framework preset: **None**.
3. Build command: `bash tool/cf_pages_build.sh`
4. Build output directory: `build/web`
5. Root directory: `/`
6. Settings → Environment variables, add for the Production (and Preview)
   environment:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`

   These are the same values as the local `.env` (see `.env.example` /
   `CLAUDE.md` item 2). `tool/cf_pages_build.sh` writes them into the
   bundled `.env` asset at build time — the build fails without them.

Cloudflare's build image doesn't include Flutter, so the build script
clones a pinned Flutter SDK version (matching local/device builds) before
building. That adds a couple of minutes to each build; there's no Flutter-
specific build cache configured yet.

## Manual / CLI deploy (optional, `wrangler.toml`)

```
flutter build web --release
npx wrangler pages deploy build/web --project-name=vasis-beats-web
```

Requires `npx wrangler login` (or a `CLOUDFLARE_API_TOKEN`) once, done
locally by whoever runs it — not set up in this repo.

## Domain

This has **not** been pointed at vasisstudio.com. Deploy to the Pages
project's own `*.pages.dev` URL first, confirm it works, then repoint DNS
when ready.
