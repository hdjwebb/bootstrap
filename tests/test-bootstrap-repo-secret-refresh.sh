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

if [ "$#" -ge 7 ] && [ "$1" = "get" ] && [ "$2" = "externalsecret" ] && [ "$4" = "-n" ] && [ "$6" = "-o" ]; then
  printf 'True'
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "deployment" ] && [ "$3" = "argocd-repo-server" ]; then
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "application" ] && [ "$3" = "app-of-apps" ]; then
  exit 0
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  configure_profile local-test
  add_gitlab_kube_comp_repo
' -- "${SCRIPT}"

assert_logged() {
  local pattern="$1"
  local message="$2"

  if ! rg -q -- "$pattern" "${LOG_FILE}"; then
    echo "FAIL: ${message}"
    exit 1
  fi
}

assert_logged '^get externalsecret components-repo-secret -n argocd -o jsonpath=' "add_gitlab_kube_comp_repo should wait for the components repo ExternalSecret"
assert_logged '^get externalsecret cluster-repo-secret -n argocd -o jsonpath=' "add_gitlab_kube_comp_repo should wait for the cluster repo ExternalSecret"
assert_logged '^get externalsecret registry-secret -n argocd -o jsonpath=' "add_gitlab_kube_comp_repo should wait for the registry ExternalSecret"
assert_logged '^delete pod -l app\.kubernetes\.io/name=argocd-repo-server -n argocd$' "add_gitlab_kube_comp_repo should restart the Argo CD repo-server after repo secrets sync"
assert_logged '^annotate application app-of-apps -n argocd argocd\.argoproj\.io/refresh=hard --overwrite$' "add_gitlab_kube_comp_repo should hard refresh app-of-apps when it already exists"

echo "PASS: bootstrap repo secret refresh checks passed"
