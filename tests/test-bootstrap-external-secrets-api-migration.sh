#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! rg -q --fixed-strings "$pattern" "$file"; then
    echo "FAIL: ${message}"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if rg -q --fixed-strings "$pattern" "$file"; then
    echo "FAIL: ${message}"
    exit 1
  fi
}

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${BOOTSTRAP_TEST_LOG_FILE:?}"

printf '%s\n' "$*" >> "${LOG_FILE}"

case "$*" in
  "get deployment external-secrets -n external-secrets -o jsonpath={.status.conditions[?(@.type==\"Available\")].status}"|\
  "get deployment external-secrets-cert-controller -n external-secrets -o jsonpath={.status.conditions[?(@.type==\"Available\")].status}"|\
  "get deployment external-secrets-webhook -n external-secrets -o jsonpath={.status.conditions[?(@.type==\"Available\")].status}")
    printf 'True\n'
    ;;
esac

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  install_external_secrets
' -- "${SCRIPT}"

assert_not_contains "${SCRIPT}" "external-secrets.io/v1beta1" "bootstrap.sh should not emit deprecated external-secrets.io/v1beta1 manifests"
assert_contains "${SCRIPT}" "apiVersion: external-secrets.io/v1" "bootstrap.sh should emit stable external-secrets.io/v1 manifests"

if ! rg -q '^apply --server-side -k ' "${LOG_FILE}"; then
  echo "FAIL: install_external_secrets should use server-side apply for the external-secrets manifest bundle"
  exit 1
fi

echo "PASS: bootstrap external-secrets API migration checks passed"
