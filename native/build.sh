#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$repo_root/build/Superlocal.app"
source_bundle="$app_bundle/Contents/Resources/superlocal"

if [[ ! -d "$repo_root/node_modules" ]]; then
  echo 'Run bun --no-env-file install --frozen-lockfile first.' >&2
  exit 1
fi
if [[ -e "$app_bundle" ]]; then
  echo 'build/Superlocal.app already exists. Move it aside before rebuilding.' >&2
  exit 1
fi
mkdir -p "$app_bundle/Contents/MacOS" "$source_bundle"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter \
  -framework Cocoa -framework WebKit "$repo_root/native/main.m" \
  -o "$app_bundle/Contents/MacOS/Superlocal"
cp "$repo_root/native/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$repo_root/native/SuperlocalIcon.icns" "$app_bundle/Contents/Resources/SuperlocalIcon.icns"
cp "$repo_root/package.json" "$repo_root/bun.lock" "$source_bundle/"
for directory in apps packages scripts; do
  rsync -a --exclude='.env' --exclude='.env.*' --exclude='*.sqlite*' \
    --exclude='data/' --exclude='runtime/' --exclude='reference/' --exclude='*.log' \
    --exclude='superlocal.local.json' --exclude='credentials*.json' --exclude='client_secret*.json' \
    "$repo_root/$directory" "$source_bundle/"
done
# Dependency packages may contain required folders named data (for example
# fast-check's Unicode tables). Source-runtime exclusions must not strip them.
rsync -a "$repo_root/node_modules" "$source_bundle/"
(cd "$source_bundle" && bun --no-env-file -e "await import('./apps/local-host/src/host.ts')")
codesign --force --deep --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
echo "Built $app_bundle"
