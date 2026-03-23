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

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "cert-manager" ]; then
  exit 1
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  uninstall_cert_manager
' -- "${SCRIPT}"

if rg -q '^get pods -n cert-manager$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_cert_manager should not poll cert-manager pods directly"
  exit 1
fi

if ! rg -q '^delete namespace cert-manager --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_cert_manager should request namespace deletion without blocking kubectl"
  exit 1
fi

if ! rg -q '^get namespace cert-manager$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_cert_manager should wait for namespace deletion"
  exit 1
fi

echo "PASS: bootstrap cert-manager uninstall checks passed"
