#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"
DELETE_CALLS_FILE="${WORKDIR}/delete-calls"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${BOOTSTRAP_TEST_LOG_FILE:?}"
DELETE_CALLS_FILE="${BOOTSTRAP_TEST_DELETE_CALLS_FILE:?}"

printf '%s\n' "$*" >> "${LOG_FILE}"

if [ "$#" -ge 4 ] && [ "$1" = "delete" ] && [ "$2" = "-f" ] && [ "$3" = "https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml" ]; then
  calls=0
  if [ -f "${DELETE_CALLS_FILE}" ]; then
    calls="$(cat "${DELETE_CALLS_FILE}")"
  fi
  calls=$((calls + 1))
  printf '%s\n' "${calls}" > "${DELETE_CALLS_FILE}"

  if [ "${calls}" -eq 1 ]; then
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

cat <<'EOF' > "${WORKDIR}/sleep"
#!/usr/bin/env bash
exit 0
EOF

chmod +x "${WORKDIR}/kubectl" "${WORKDIR}/sleep"

output="$(
  BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" \
  BOOTSTRAP_TEST_DELETE_CALLS_FILE="${DELETE_CALLS_FILE}" \
  PATH="${WORKDIR}:${PATH}" \
  bash -c '
    set -euo pipefail
    source "$1"
    uninstall_cert_manager
  ' -- "${SCRIPT}" 2>&1
)"

if [ "$(cat "${DELETE_CALLS_FILE}")" -ne 2 ]; then
  echo "FAIL: uninstall_cert_manager should retry the cert-manager manifest delete after a transient transport failure"
  exit 1
fi

if ! printf '%s\n' "${output}" | rg -q 'Retrying kubectl delete after transient transport failure'; then
  echo "FAIL: uninstall_cert_manager should report when it retries a transient kubectl transport failure"
  exit 1
fi

echo "PASS: bootstrap kubectl retry checks passed"
