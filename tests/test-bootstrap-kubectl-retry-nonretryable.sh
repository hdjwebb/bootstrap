#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${BOOTSTRAP_TEST_LOG_FILE:?}"

printf '%s\n' "$*" >> "${LOG_FILE}"
echo 'Error from server (NotFound): the server could not find the requested resource' >&2
exit 1
EOF

chmod +x "${WORKDIR}/kubectl"

if BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" \
   PATH="${WORKDIR}:${PATH}" \
   bash -c '
     set -euo pipefail
     source "$1"
     run_kubectl_with_retry delete -f https://example.invalid/manifest.yaml --ignore-not-found=true
   ' -- "${SCRIPT}"; then
  echo "FAIL: run_kubectl_with_retry should return a failure for non-retryable kubectl errors"
  exit 1
fi

echo "PASS: bootstrap kubectl retry non-retryable error checks passed"
