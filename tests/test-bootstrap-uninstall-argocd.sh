#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"
STATE_FILE="${WORKDIR}/applications-state"
NAMESPACE_FILE="${WORKDIR}/namespace-state"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${BOOTSTRAP_TEST_LOG_FILE:?}"
STATE_FILE="${BOOTSTRAP_TEST_STATE_FILE:?}"

printf '%s\n' "$*" >> "${LOG_FILE}"

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "argocd" ]; then
  if [ -f "${BOOTSTRAP_TEST_NAMESPACE_FILE:?}" ]; then
    exit 0
  fi
  exit 1
fi

if [ "$#" -ge 6 ] && [ "$1" = "delete" ] && [ "$2" = "applications.argoproj.io" ] && [ "$3" = "--all" ] && [ "$4" = "-n" ] && [ "$5" = "argocd" ]; then
  printf 'remaining\n' > "${STATE_FILE}"
  exit 0
fi

if [ "$#" -ge 5 ] && [ "$1" = "get" ] && [ "$2" = "applications.argoproj.io" ] && [ "$3" = "-n" ] && [ "$4" = "argocd" ] && [ "$5" = "-o" ]; then
  if [ -f "${STATE_FILE}" ]; then
    printf 'application.argoproj.io/argocd\n'
  fi
  exit 0
fi

if [ "$#" -ge 6 ] && [ "$1" = "patch" ] && [ "$2" = "application.argoproj.io/argocd" ] && [ "$3" = "-n" ] && [ "$4" = "argocd" ] && [ "$5" = "--type=merge" ]; then
  rm -f "${STATE_FILE}"
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "delete" ] && [ "$2" = "namespace" ] && [ "$3" = "argocd" ]; then
  rm -f "${BOOTSTRAP_TEST_NAMESPACE_FILE:?}"
  exit 0
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

printf 'present\n' > "${NAMESPACE_FILE}"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" BOOTSTRAP_TEST_STATE_FILE="${STATE_FILE}" BOOTSTRAP_TEST_NAMESPACE_FILE="${NAMESPACE_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  configure_profile local-test
  uninstall_argocd
' -- "${SCRIPT}"

if rg -q '^delete all --all -n argocd --force --grace-period=0$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_argocd should not rely on a force-delete-all fallback"
  exit 1
fi

if ! rg -q '^delete -k ' "${LOG_FILE}"; then
  echo "FAIL: uninstall_argocd should delete the generated Argo CD kustomization"
  exit 1
fi

if ! rg -q '^delete applications.argoproj.io --all -n argocd --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_argocd should delete Argo CD Application resources before removing the control plane"
  exit 1
fi

if ! rg -q '^patch application.argoproj.io/argocd -n argocd --type=merge -p \{"metadata":\{"finalizers":\[\]\}\}$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_argocd should clear remaining Argo CD application finalizers when uninstall is blocked"
  exit 1
fi

if ! rg -q '^delete namespace argocd --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_argocd should request namespace deletion without blocking kubectl"
  exit 1
fi

if ! rg -q '^get namespace argocd$' "${LOG_FILE}"; then
  echo "FAIL: uninstall_argocd should wait for namespace deletion"
  exit 1
fi

delete_apps_line="$(rg -n '^delete applications\.argoproj\.io --all -n argocd --ignore-not-found=true --wait=false$' "${LOG_FILE}" | cut -d: -f1)"
delete_k_line="$(rg -n '^delete -k ' "${LOG_FILE}" | cut -d: -f1)"

if [ -z "${delete_apps_line}" ] || [ -z "${delete_k_line}" ] || [ "${delete_apps_line}" -ge "${delete_k_line}" ]; then
  echo "FAIL: uninstall_argocd should delete Application resources before deleting the Argo CD control plane"
  exit 1
fi

echo "PASS: bootstrap Argo CD uninstall checks passed"
