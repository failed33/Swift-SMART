#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
if [[ -f "${SCRIPT_DIR}/standalone_launch.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/standalone_launch.env"
  set +a
fi

: "${SMART_BASE_URL:?SMART_BASE_URL must be set}"
: "${SMART_CLIENT_ID:?SMART_CLIENT_ID must be set}"
: "${SMART_HTTPS_AUTH_BASE:?SMART_HTTPS_AUTH_BASE must be set}"

export SMART_SCOPE="${SMART_SCOPE:-launch/patient patient/*.rs openid fhirUser offline_access}"

echo "Running standalone launch tests against ${SMART_BASE_URL}"
echo "SMART_SCOPE: ${SMART_SCOPE}"
echo "SMART_CLIENT_ID: ${SMART_CLIENT_ID}"
echo "SMART_REDIRECT: ${SMART_REDIRECT}"
echo "SMART_HTTPS_AUTH_BASE: ${SMART_HTTPS_AUTH_BASE}"
# echo "SMART_AUTOMATION_ENDPOINT: ${SMART_AUTOMATION_ENDPOINT}"

# caddy run --config scripts/test_scripts/standalone_launch/Caddyfile --adapter caddyfile

if [[ " $* " == *" --filter "* ]]; then
  swift test "$@"
else
  swift test --filter StandaloneLaunchTests "$@"
fi

# caddy stop