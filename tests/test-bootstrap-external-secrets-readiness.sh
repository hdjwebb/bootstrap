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

if [[ "$*" == *"--for=condition=ready pod"* ]]; then
  echo "unexpected pod readiness wait" >&2
  exit 1
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  install_external_secrets
' -- "${SCRIPT}"

for deployment in external-secrets external-secrets-cert-controller external-secrets-webhook; do
  if ! grep -q "^wait --for=condition=available --timeout=300s deployment/${deployment} -n external-secrets$" "${LOG_FILE}"; then
    echo "FAIL: install_external_secrets should wait for deployment/${deployment} availability"
    exit 1
  fi
done

echo "PASS: bootstrap external-secrets readiness checks passed"
