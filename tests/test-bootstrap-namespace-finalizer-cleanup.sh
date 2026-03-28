#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"
DEPLOYMENT_STATE_FILE="${WORKDIR}/deployment-state"
ALLOY_STATE_FILE="${WORKDIR}/alloy-state"
NAMESPACE_STATE_FILE="${WORKDIR}/namespace-state"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${BOOTSTRAP_TEST_LOG_FILE:?}"

printf '%s\n' "$*" >> "${LOG_FILE}"

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "alloy" ]; then
  if [ "$#" -ge 5 ] && [ "$4" = "-o" ]; then
    if [ -f "${BOOTSTRAP_TEST_NAMESPACE_STATE_FILE:?}" ]; then
      printf '2026-03-28T22:56:01Z'
      exit 0
    fi
    exit 1
  fi

  if [ -f "${BOOTSTRAP_TEST_NAMESPACE_STATE_FILE:?}" ]; then
    exit 0
  fi
  exit 1
fi

if [ "$#" -ge 5 ] && [ "$1" = "api-resources" ] && [ "$2" = "--verbs=list" ] && [ "$3" = "--namespaced" ] && [ "$4" = "-o" ] && [ "$5" = "name" ]; then
  printf 'deployments.apps\nalloys.collectors.grafana.com\n'
  exit 0
fi

if [ "$#" -ge 7 ] && [ "$1" = "get" ] && [ "$2" = "-n" ] && [ "$3" = "alloy" ] && [ "$4" = "deployments.apps" ] && [ "$5" = "-o" ] && [ "$6" = "name" ]; then
  if [ -f "${BOOTSTRAP_TEST_DEPLOYMENT_STATE_FILE:?}" ]; then
    printf 'deployment.apps/grafana-k8s-monitoring-alloy-operator\n'
  fi
  exit 0
fi

if [ "$#" -ge 7 ] && [ "$1" = "get" ] && [ "$2" = "-n" ] && [ "$3" = "alloy" ] && [ "$4" = "alloys.collectors.grafana.com" ] && [ "$5" = "-o" ] && [ "$6" = "name" ]; then
  if [ -f "${BOOTSTRAP_TEST_ALLOY_STATE_FILE:?}" ]; then
    printf 'alloys.collectors.grafana.com/grafana-k8s-monitoring-alloy-logs\n'
  fi
  exit 0
fi

if [ "$#" -ge 6 ] && [ "$1" = "patch" ] && [ "$2" = "deployment.apps/grafana-k8s-monitoring-alloy-operator" ] && [ "$3" = "-n" ] && [ "$4" = "alloy" ] && [ "$5" = "--type=merge" ]; then
  rm -f "${BOOTSTRAP_TEST_DEPLOYMENT_STATE_FILE:?}"
  exit 0
fi

if [ "$#" -ge 6 ] && [ "$1" = "patch" ] && [ "$2" = "alloys.collectors.grafana.com/grafana-k8s-monitoring-alloy-logs" ] && [ "$3" = "-n" ] && [ "$4" = "alloy" ] && [ "$5" = "--type=merge" ]; then
  rm -f "${BOOTSTRAP_TEST_ALLOY_STATE_FILE:?}"
  exit 0
fi

exit 0
EOF

chmod +x "${WORKDIR}/kubectl"

printf 'present\n' > "${DEPLOYMENT_STATE_FILE}"
printf 'present\n' > "${ALLOY_STATE_FILE}"
printf 'present\n' > "${NAMESPACE_STATE_FILE}"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" \
BOOTSTRAP_TEST_DEPLOYMENT_STATE_FILE="${DEPLOYMENT_STATE_FILE}" \
BOOTSTRAP_TEST_ALLOY_STATE_FILE="${ALLOY_STATE_FILE}" \
BOOTSTRAP_TEST_NAMESPACE_STATE_FILE="${NAMESPACE_STATE_FILE}" \
PATH="${WORKDIR}:${PATH}" \
bash -c '
  set -euo pipefail
  source "$1"
  if namespace_is_deleted alloy; then
    echo "FAIL: namespace_is_deleted should report false while namespace still exists"
    exit 1
  fi
' -- "${SCRIPT}"

if ! rg -q '^api-resources --verbs=list --namespaced -o name$' "${LOG_FILE}"; then
  echo "FAIL: namespace_is_deleted should enumerate namespaced resource types during terminating namespace cleanup"
  exit 1
fi

if ! rg -q '^patch deployment\.apps/grafana-k8s-monitoring-alloy-operator -n alloy --type=merge -p \{"metadata":\{"finalizers":\[\]\}\}$' "${LOG_FILE}"; then
  echo "FAIL: namespace_is_deleted should clear deployment finalizers in terminating namespaces"
  exit 1
fi

if ! rg -q '^patch alloys\.collectors\.grafana\.com/grafana-k8s-monitoring-alloy-logs -n alloy --type=merge -p \{"metadata":\{"finalizers":\[\]\}\}$' "${LOG_FILE}"; then
  echo "FAIL: namespace_is_deleted should clear custom resource finalizers in terminating namespaces"
  exit 1
fi

echo "PASS: bootstrap namespace finalizer cleanup checks passed"
