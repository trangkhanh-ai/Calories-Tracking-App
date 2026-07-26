#!/usr/bin/env bash
#
# Vercel build for the Flutter Web frontend.
#
# Run from the repository root — the Flutter project lives at the repo root, so
# the Vercel project's Root Directory must stay "." (see docs/DEPLOYMENT_GUIDE.md).
#
# Deliberately NOT using `set -x`: the trace would print BACKEND_BASE_URL and
# every other environment value into the build log.
set -euo pipefail

# Pinned exactly. A floating `stable` branch means the same commit can build
# against a different SDK tomorrow, which is not a reproducible build.
readonly FLUTTER_VERSION="3.44.1"
readonly FLUTTER_HOME="${FLUTTER_HOME:-$PWD/.flutter-sdk}"

log() {
  printf '==> %s\n' "$1"
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Validate BACKEND_BASE_URL
#
# Must be a bare HTTPS origin: no /api suffix, no trailing slash, no path,
# query, fragment, or credentials, and not a loopback host.
# ---------------------------------------------------------------------------
validate_backend_base_url() {
  local url="${BACKEND_BASE_URL:-}"

  [[ -n "$url" ]] || fail "BACKEND_BASE_URL is required."

  [[ "$url" == https://* ]] || fail "BACKEND_BASE_URL must use https://."

  [[ "$url" != */ ]] || fail "BACKEND_BASE_URL must not end with a trailing slash."

  # Strip the scheme; anything from the first /, ?, or # onwards is a path,
  # query, or fragment — none of which are allowed.
  local remainder="${url#https://}"

  [[ -n "$remainder" ]] || fail "BACKEND_BASE_URL is missing a host."

  [[ "$remainder" != *"@"* ]] || fail "BACKEND_BASE_URL must not embed credentials."
  [[ "$remainder" != *"/"* ]] || fail "BACKEND_BASE_URL must be a bare origin with no path (remove /api or any other path)."
  [[ "$remainder" != *"?"* ]] || fail "BACKEND_BASE_URL must not contain a query string."
  [[ "$remainder" != *"#"* ]] || fail "BACKEND_BASE_URL must not contain a fragment."

  # Host without an optional :port.
  local host="${remainder%%:*}"
  local lower_host
  lower_host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"

  [[ -n "$lower_host" ]] || fail "BACKEND_BASE_URL is missing a host."

  case "$lower_host" in
    localhost | 127.* | 0.0.0.0 | ::1 | "[::1]")
      fail "BACKEND_BASE_URL must not point at a loopback host."
      ;;
  esac

  # The host is a public origin, not a secret, so echoing it is safe and makes
  # a misconfigured deploy obvious in the log.
  log "BACKEND_BASE_URL host validated: $lower_host"
}

install_flutter() {
  if command -v flutter > /dev/null 2>&1; then
    log "Flutter already on PATH: $(flutter --version | head -n 1)"
    return
  fi

  if [[ ! -d "$FLUTTER_HOME" ]]; then
    log "Installing Flutter $FLUTTER_VERSION"
    # --branch takes the immutable version tag, not a moving channel.
    git clone \
      --branch "$FLUTTER_VERSION" \
      --depth 1 \
      https://github.com/flutter/flutter.git \
      "$FLUTTER_HOME"
  fi

  export PATH="$PATH:$FLUTTER_HOME/bin"

  # Vercel's build container may run as a different user than the SDK checkout
  # owner; without this Flutter refuses to run in the directory.
  git config --global --add safe.directory "$FLUTTER_HOME" || true

  log "Flutter ready: $(flutter --version | head -n 1)"

  # `flutter doctor -v` is intentionally skipped: it costs build minutes and
  # prints environment detail nobody reads in a CI log.
}

main() {
  validate_backend_base_url
  install_flutter

  log "Restoring locked dependencies"
  flutter pub get --enforce-lockfile

  log "Building Flutter Web release"
  # --base-href / because Vercel serves the app at the domain root, unlike the
  # project-subpath layout GitHub Pages required.
  flutter build web \
    --release \
    --base-href / \
    --dart-define=BACKEND_BASE_URL="$BACKEND_BASE_URL"

  log "Build complete: build/web"
}

main "$@"
