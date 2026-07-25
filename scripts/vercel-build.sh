#!/bin/bash
set -ex

# Ensure BACKEND_BASE_URL is set
if [ -z "$BACKEND_BASE_URL" ]; then
  echo "Error: BACKEND_BASE_URL is required."
  exit 1
fi

if [[ ! "$BACKEND_BASE_URL" =~ ^https:// ]]; then
  echo "Error: BACKEND_BASE_URL must start with https://"
  exit 1
fi

if [[ "$BACKEND_BASE_URL" == */ ]]; then
  echo "Error: BACKEND_BASE_URL must not have a trailing slash"
  exit 1
fi

# Vercel environment doesn't have Flutter pre-installed.
if ! command -v flutter &> /dev/null; then
  echo "Flutter not found. Installing..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
  export PATH="$PATH:`pwd`/flutter/bin"
fi

flutter doctor -v
flutter pub get --enforce-lockfile
flutter build web --release --base-href / --dart-define=BACKEND_BASE_URL=$BACKEND_BASE_URL
