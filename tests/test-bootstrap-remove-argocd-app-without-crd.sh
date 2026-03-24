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

printf '%s\n' "$*" >> "${BOOTSTRAP_TEST_LOG_FILE:?}"

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "crd" ] && [ "$3" = "applications.argoproj.io" ]; then
  exit 1
fi

if [ "$#" -ge 2 ] && [ "$1" = "delete" ] && [ "$2" = "-f" ]; then
  echo "FAIL: remove_argocd_app should not try to delete the tracked manifest when the Application CRD is absent" >&2
  exit 99
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

output="$(
  BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
    set -euo pipefail
    source "$1"
    configure_profile local-test-plus
    require_profile_settings
    remove_argocd_app
  ' -- "${SCRIPT}"
)"

if ! printf '%s\n' "${output}" | rg -q 'Skipping ArgoCD application removal because the Application CRD is not installed\.'; then
  echo "FAIL: remove_argocd_app should explain why it skipped removal when the Application CRD is absent"
  exit 1
fi

if rg -q '^delete -f ' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should not issue kubectl delete -f when the Application CRD is absent"
  exit 1
fi

echo "PASS: bootstrap remove ArgoCD app without CRD checks passed"
