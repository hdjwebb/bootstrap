#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"
CA_CALLS_FILE="${WORKDIR}/ca-calls"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${BOOTSTRAP_TEST_LOG_FILE:?}"
CA_CALLS_FILE="${BOOTSTRAP_TEST_CA_CALLS_FILE:?}"

printf '%s\n' "$*" >> "${LOG_FILE}"

if [ "$#" -ge 5 ] && [ "$1" = "get" ] && [ "$2" = "validatingwebhookconfiguration" ] && [ "$4" = "-o" ] && \
   { [ "$3" = "cert-manager-webhook" ] || [ "$3" = "secretstore-validate" ] || [ "$3" = "externalsecret-validate" ]; }; then
  calls=0
  if [ -f "${CA_CALLS_FILE}" ]; then
    calls="$(cat "${CA_CALLS_FILE}")"
  fi
  calls=$((calls + 1))
  printf '%s\n' "${calls}" > "${CA_CALLS_FILE}"

  if [ "${calls}" -ge 3 ]; then
    printf 'injected-ca-bundle'
  fi
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "apply" ] && [ "$2" = "-f" ]; then
  manifest_path="$3"

  if [[ "${manifest_path}" = *"/clusterIssuer.yaml" ]]; then
    calls=0
    if [ -f "${CA_CALLS_FILE}" ]; then
      calls="$(cat "${CA_CALLS_FILE}")"
    fi

    if [ "${calls}" -lt 3 ]; then
      echo 'Error from server (InternalError): error when creating "'"${manifest_path}"'": Internal error occurred: failed calling webhook "webhook.cert-manager.io": failed to call webhook: Post "https://cert-manager-webhook.cert-manager.svc:443/validate?timeout=30s": tls: failed to verify certificate: x509: certificate signed by unknown authority' >&2
      exit 1
    fi
  fi

  exit 0
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

if BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" \
   BOOTSTRAP_TEST_CA_CALLS_FILE="${CA_CALLS_FILE}" \
   AKEYLESS_ACCESS_ID="test-id" \
   AKEYLESS_ACCESS_SECRET_KEY="test-key" \
   PATH="${WORKDIR}:${PATH}" \
   bash -c '
     set -euo pipefail
     source "$1"
     install_secret_clusterStore_external_secrets
   ' -- "${SCRIPT}"; then
  :
else
  echo "FAIL: install_secret_clusterStore_external_secrets should wait for cert-manager webhook CA injection before applying the ClusterIssuer"
  exit 1
fi

webhook_wait_line="$(rg -n "^get validatingwebhookconfiguration cert-manager-webhook -o jsonpath=" "${LOG_FILE}" | tail -n 1 | cut -d: -f1)"
clusterissuer_apply_line="$(rg -n '/clusterIssuer.yaml$' "${LOG_FILE}" | head -n 1 | cut -d: -f1)"

if [ -z "${webhook_wait_line}" ] || [ -z "${clusterissuer_apply_line}" ] || [ "${webhook_wait_line}" -ge "${clusterissuer_apply_line}" ]; then
  echo "FAIL: install_secret_clusterStore_external_secrets should poll the cert-manager webhook CA bundle before applying the ClusterIssuer"
  exit 1
fi

if [ "$(cat "${CA_CALLS_FILE}")" -lt 3 ]; then
  echo "FAIL: install_secret_clusterStore_external_secrets should keep polling until the cert-manager webhook CA bundle is injected"
  exit 1
fi

echo "PASS: bootstrap cert-manager webhook readiness checks passed"
