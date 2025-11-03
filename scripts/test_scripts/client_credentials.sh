#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${script_dir}/client_credentials.env"

if [[ -f "${env_file}" ]]; then
	# shellcheck disable=SC1090
	source "${env_file}"
fi

: "${SMART_BASE_URL:?Set SMART_BASE_URL in client_credentials.env or environment}"
: "${SMART_CLIENT_ID:?Set SMART_CLIENT_ID in client_credentials.env or environment}"
: "${SMART_CLIENT_SECRET:?Set SMART_CLIENT_SECRET in client_credentials.env or environment}"
: "${SMART_SCOPE:=system/*.rs}"

export SMART_BASE_URL SMART_CLIENT_ID SMART_CLIENT_SECRET SMART_SCOPE
[[ ${SMART_TEST_QUERY_PATH:-} ]] && export SMART_TEST_QUERY_PATH

echo "Running live SMART client_credentials test against ${SMART_BASE_URL}"
swift test -c debug --filter LiveServerClientCredentialsTests "$@"