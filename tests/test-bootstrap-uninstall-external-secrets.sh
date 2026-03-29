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

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "external-secrets" ]; then
  exit 1
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  uninstall_external_secrets
' -- "${SCRIPT}"

if ! rg -q '^delete -f https://github.com/external-secrets/external-secrets/releases/download/v2.2.0/external-secrets.yaml --ignore-not-found=true$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_external_secrets should delete the tracked external-secrets release manifest"
  exit 1
fi

if ! rg -q '^delete namespace external-secrets --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_external_secrets should request namespace deletion without blocking kubectl"
  exit 1
fi

if ! rg -q '^get namespace external-secrets$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_external_secrets should wait for namespace deletion"
  exit 1
fi

echo "PASS: bootstrap external-secrets uninstall checks passed"
