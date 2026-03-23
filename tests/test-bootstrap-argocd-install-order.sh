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

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "argocd" ]; then
  exit 1
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  configure_profile local-test
  install_argocd
' -- "${SCRIPT}"

create_line="$(grep -n '^create namespace argocd$' "${LOG_FILE}" | head -n1 | cut -d: -f1 || true)"
apply_line="$(grep -n '^apply -k ' "${LOG_FILE}" | head -n1 | cut -d: -f1 || true)"

if [ -z "${create_line}" ]; then
  echo "FAIL: install_argocd should create the argocd namespace when it does not exist"
  exit 1
fi

if [ -z "${apply_line}" ]; then
  echo "FAIL: install_argocd should apply the Argo CD kustomization"
  exit 1
fi

if [ "${create_line}" -ge "${apply_line}" ]; then
  echo "FAIL: install_argocd should create the argocd namespace before applying manifests"
  exit 1
fi

echo "PASS: bootstrap Argo CD install order checks passed"
