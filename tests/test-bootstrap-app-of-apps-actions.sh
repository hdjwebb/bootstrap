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

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  configure_profile local-test
  require_profile_settings
  add_argocd_app_of_apps
  remove_argocd_app
' -- "${SCRIPT}"

EXPECTED_MANIFEST="/Users/henry/Documents/Coding/GitLab/ifpossible-sre/Clusters/microK8s/cluster/local-test/app-of-apps.yaml"

if ! rg -q "^apply -f ${EXPECTED_MANIFEST}$" "${LOG_FILE}"; then
  echo "FAIL: add_argocd_app_of_apps should apply the tracked manifest file"
  exit 1
fi

if ! rg -q "^delete -f ${EXPECTED_MANIFEST} --ignore-not-found=true$" "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should delete the tracked manifest file"
  exit 1
fi

echo "PASS: bootstrap app-of-apps action checks passed"
