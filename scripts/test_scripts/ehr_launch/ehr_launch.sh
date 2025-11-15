#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/ehr_launch.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

: "${SMART_BASE_URL:?Set SMART_BASE_URL in ehr_launch.env}"
: "${SMART_CLIENT_ID:?Set SMART_CLIENT_ID in ehr_launch.env}"
: "${SMART_EHR_ISS:?Set SMART_EHR_ISS in ehr_launch.env}"
: "${SMART_EHR_CLIENT_ID:?Set SMART_EHR_CLIENT_ID in ehr_launch.env}"
: "${SMART_EHR_REDIRECT:?Set SMART_EHR_REDIRECT in ehr_launch.env}"
: "${SMART_EHR_PATIENT:?Set SMART_EHR_PATIENT in ehr_launch.env}"

export SMART_SCOPE="${SMART_SCOPE:-launch/patient patient/*.rs openid fhirUser offline_access}"
export SMART_EHR_SCOPE="${SMART_EHR_SCOPE:-openid Context.write}"

echo "Running EHR launch tests against ${SMART_BASE_URL}"
echo "  SMART client: ${SMART_CLIENT_ID}"
echo "  EHR client: ${SMART_EHR_CLIENT_ID}"
echo "  Launch patient: ${SMART_EHR_PATIENT}"

if [[ " $* " == *" --filter "* ]]; then
  swift test "$@"
else
  swift test --filter EHRLaunchTests "$@"
fi


