#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"
ATTEMPT_FILE="${WORKDIR}/delete-attempts"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${BOOTSTRAP_TEST_LOG_FILE:?}"
ATTEMPT_FILE="${BOOTSTRAP_TEST_ATTEMPT_FILE:?}"

printf '%s\n' "$*" >> "${LOG_FILE}"

if [ "$#" -ge 4 ] && [ "$1" = "delete" ] && [ "$2" = "-f" ] && [ "$3" = "https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml" ]; then
  attempts=0
  if [ -f "${ATTEMPT_FILE}" ]; then
    attempts="$(cat "${ATTEMPT_FILE}")"
  fi
  attempts=$((attempts + 1))
  printf '%s\n' "${attempts}" > "${ATTEMPT_FILE}"

  if [ "${attempts}" -eq 1 ]; then
    echo 'error: Get "https://127.0.0.1:50319/apis/rbac.authorization.k8s.io/v1/clusterroles/cert-manager-controller-issuers": dial tcp 127.0.0.1:50319: connect: connection refused - error from a previous attempt: unexpected EOF' >&2
    exit 1
  fi

  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "cert-manager" ]; then
  exit 1
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

if BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" \
   BOOTSTRAP_TEST_ATTEMPT_FILE="${ATTEMPT_FILE}" \
   PATH="${WORKDIR}:${PATH}" \
   bash -c '
     set -euo pipefail
     source "$1"
     uninstall_cert_manager
   ' -- "${SCRIPT}"; then
  :
else
  echo "FAIL: uninstall_cert_manager should retry a transient kubectl delete transport failure"
  exit 1
fi

delete_attempts="$(rg -c '^delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml --ignore-not-found=true$' "${LOG_FILE}")"
if [ "${delete_attempts}" -lt 2 ]; then
  echo "FAIL: uninstall_cert_manager should retry the cert-manager manifest delete after a transient transport error"
  exit 1
fi

if ! rg -q '^delete namespace cert-manager --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_cert_manager should continue with namespace deletion after the delete retry succeeds"
  exit 1
fi

echo "PASS: bootstrap cert-manager uninstall retry checks passed"
