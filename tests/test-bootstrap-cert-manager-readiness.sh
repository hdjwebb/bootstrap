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

case "$*" in
  *"--for=condition=ready pod"* )
    echo "unexpected pod readiness wait" >&2
    exit 1
    ;;
  "get deployment cert-manager -n cert-manager -o jsonpath={.status.conditions[?(@.type==\"Available\")].status}"|\
  "get deployment cert-manager-cainjector -n cert-manager -o jsonpath={.status.conditions[?(@.type==\"Available\")].status}"|\
  "get deployment cert-manager-webhook -n cert-manager -o jsonpath={.status.conditions[?(@.type==\"Available\")].status}")
    printf 'True\n'
    ;;
esac

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  install_cert_manager
' -- "${SCRIPT}"

for deployment in cert-manager cert-manager-cainjector cert-manager-webhook; do
  if ! grep -q "^get deployment ${deployment} -n cert-manager -o jsonpath=" "${LOG_FILE}"; then
    echo "FAIL: install_cert_manager should wait for deployment/${deployment} availability"
    exit 1
  fi
done

if grep -q "^wait --for=condition=available --timeout=300s deployment/" "${LOG_FILE}"; then
  echo "FAIL: install_cert_manager should not rely on kubectl wait for deployments"
  exit 1
fi

echo "PASS: bootstrap cert-manager readiness checks passed"
