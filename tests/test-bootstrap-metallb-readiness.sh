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

case "$*" in
  *"--for=condition=ready pod"* )
    echo "unexpected pod readiness wait" >&2
    exit 1
    ;;
  "get deployment controller -n metallb-system -o jsonpath={.status.conditions[?(@.type==\"Available\")].status}")
    printf 'True\n'
    ;;
  "get daemonset speaker -n metallb-system -o jsonpath={.status.desiredNumberScheduled}")
    printf '1\n'
    ;;
  "get daemonset speaker -n metallb-system -o jsonpath={.status.numberReady}")
    printf '1\n'
    ;;
esac

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
  set -euo pipefail
  source "$1"
  configure_profile microk8s-prod
  install_metallb
' -- "${SCRIPT}"

if ! grep -q "^wait --for condition=established --timeout=60s crd/ipaddresspools.metallb.io$" "${LOG_FILE}"; then
  echo "FAIL: install_metallb should wait for the IPAddressPool CRD"
  exit 1
fi

if ! grep -q "^wait --for condition=established --timeout=60s crd/l2advertisements.metallb.io$" "${LOG_FILE}"; then
  echo "FAIL: install_metallb should wait for the L2Advertisement CRD"
  exit 1
fi

if ! grep -q "^get deployment controller -n metallb-system -o jsonpath=" "${LOG_FILE}"; then
  echo "FAIL: install_metallb should wait for deployment/controller availability"
  exit 1
fi

if ! grep -q "^get daemonset speaker -n metallb-system -o jsonpath=" "${LOG_FILE}"; then
  echo "FAIL: install_metallb should wait for daemonset/speaker rollout"
  exit 1
fi

if grep -q "^wait --for=condition=available --timeout=300s deployment/controller -n metallb-system$" "${LOG_FILE}"; then
  echo "FAIL: install_metallb should not rely on kubectl wait for the controller deployment"
  exit 1
fi

if grep -q "^rollout status daemonset/speaker -n metallb-system --timeout=300s$" "${LOG_FILE}"; then
  echo "FAIL: install_metallb should not rely on kubectl rollout status for the speaker daemonset"
  exit 1
fi

echo "PASS: bootstrap MetalLB readiness checks passed"
