#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/scripts/rehearse-minikube-local-test-plus.sh"
LOCK_DIR="$(mktemp -d)"
OUTPUT_FILE="$(mktemp)"

cleanup() {
  rm -rf "${LOCK_DIR}"
  rm -f "${OUTPUT_FILE}"
}

trap cleanup EXIT

printf '%s\n' "$$" > "${LOCK_DIR}/pid"

set +e
BOOTSTRAP_REHEARSAL_LOCK_DIR="${LOCK_DIR}" \
  bash "${SCRIPT}" >"${OUTPUT_FILE}" 2>&1
exit_code=$?
set -e

if [ "${exit_code}" -eq 0 ]; then
  echo "FAIL: rehearsal script should refuse to run when the lock is already held"
  exit 1
fi

if ! rg -q 'another rehearsal is already running' "${OUTPUT_FILE}"; then
  echo "FAIL: rehearsal script should explain that another destructive rehearsal already holds the lock"
  exit 1
fi

echo "PASS: bootstrap rehearsal lock checks passed"
