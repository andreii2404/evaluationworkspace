#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_URL:?Set SUPABASE_URL in the Vercel project settings}"
: "${SUPABASE_PUBLISHABLE_KEY:?Set SUPABASE_PUBLISHABLE_KEY in the Vercel project settings}"

# Match the Flutter SDK used for local release builds.
flutter_version=3.41.6
flutter_sdk="$(mktemp -d)/flutter"

git clone --quiet --depth 1 --branch "$flutter_version" \
  https://github.com/flutter/flutter.git "$flutter_sdk"

"$flutter_sdk/bin/flutter" config --no-analytics
"$flutter_sdk/bin/flutter" build web --release --no-wasm-dry-run \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
