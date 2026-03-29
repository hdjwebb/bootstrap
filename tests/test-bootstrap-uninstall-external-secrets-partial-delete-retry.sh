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

if [ "$#" -ge 4 ] && [ "$1" = "delete" ] && [ "$2" = "-f" ] && [ "$3" = "https://github.com/external-secrets/external-secrets/releases/download/v2.2.0/external-secrets.yaml" ]; then
  attempts=0
  if [ -f "${ATTEMPT_FILE}" ]; then
    attempts="$(cat "${ATTEMPT_FILE}")"
  fi
  attempts=$((attempts + 1))
  printf '%s\n' "${attempts}" > "${ATTEMPT_FILE}"

  if [ "${attempts}" -eq 1 ]; then
    echo 'error: Get "https://127.0.0.1:51527/apis/apps/v1/namespaces/default/deployments/external-secrets-webhook": dial tcp 127.0.0.1:51527: connect: connection refused - error from a previous attempt: unexpected EOF' >&2
    exit 1
  fi

  cat >&2 <<'ERR'
E0324 22:10:31.272290   91480 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: the server could not find the requested resource"
unable to recognize "https://github.com/external-secrets/external-secrets/releases/download/v2.2.0/external-secrets.yaml": the server could not find the requested resource
Error from server (NotFound): the server could not find the requested resource
ERR
  exit 1
fi

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "external-secrets" ]; then
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
     uninstall_external_secrets
   ' -- "${SCRIPT}"; then
  :
else
  echo "FAIL: uninstall_external_secrets should tolerate missing-resource discovery errors after a retryable partial manifest delete"
  exit 1
fi

delete_attempts="$(rg -c '^delete -f https://github.com/external-secrets/external-secrets/releases/download/v2.2.0/external-secrets.yaml --ignore-not-found=true$' "${LOG_FILE}")"
if [ "${delete_attempts}" -lt 2 ]; then
  echo "FAIL: uninstall_external_secrets should retry the manifest delete after a transient transport failure"
  exit 1
fi

if ! rg -q '^delete namespace external-secrets --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_external_secrets should continue to namespace deletion after a partial manifest delete"
  exit 1
fi

echo "PASS: bootstrap external-secrets partial delete retry checks passed"
