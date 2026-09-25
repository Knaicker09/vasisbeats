#!/usr/bin/env bash
# Build script for Cloudflare Pages (Git integration).
#
# Cloudflare Pages' build image doesn't include Flutter, so this fetches a
# pinned SDK version (matching local/device builds) and builds the web
# target release-mode. Configure in the Pages project settings:
#
#   Framework preset:      None
#   Build command:         bash tool/cf_pages_build.sh
#   Build output directory: build/web
#
# Also set these as Environment variables (Settings > Environment variables,
# NOT "secrets" exposed to the client bundle -- they're baked into the
# bundled .env asset at build time, same as any local/CI build):
#   SUPABASE_URL
#   SUPABASE_ANON_KEY
set -euo pipefail

FLUTTER_VERSION="3.47.4"

if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" _flutter
fi
export PATH="$PWD/_flutter/bin:$PATH"

flutter config --enable-web --no-analytics >/dev/null

# .env is a bundled pubspec asset (see CLAUDE.md / .env.example) and is
# gitignored -- the build fails without it, so create it from the env vars
# set in the Cloudflare Pages project settings.
: "${SUPABASE_URL:?SUPABASE_URL must be set in the Cloudflare Pages build environment}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY must be set in the Cloudflare Pages build environment}"
cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
EOF

flutter pub get
flutter build web --release
