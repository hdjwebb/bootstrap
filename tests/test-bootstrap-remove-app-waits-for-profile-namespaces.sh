#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/kubectl.log"
DEPLOYMENT_STATE_FILE="${WORKDIR}/deployment-state"
ALLOY_STATE_FILE="${WORKDIR}/alloy-state"
NAMESPACE_STATE_FILE="${WORKDIR}/namespace-state"
CHILD_APP_STATE_FILE="${WORKDIR}/child-app-state"
CHILD_APP_POLL_COUNT_FILE="${WORKDIR}/child-app-poll-count"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/kubectl"
#!/usr/bin/env bash

set -euo pipefail

printf '%s\n' "$*" >> "${BOOTSTRAP_TEST_LOG_FILE:?}"

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "crd" ] && [ "$3" = "applications.argoproj.io" ]; then
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "argocd" ]; then
  exit 0
fi

if [ "$#" -ge 2 ] && [ "$1" = "delete" ] && [ "$2" = "-f" ]; then
  exit 0
fi

if [ "$#" -ge 6 ] && [ "$1" = "get" ] && [ "$2" = "applications.argoproj.io" ] && [ "$3" = "-n" ] && [ "$4" = "argocd" ] && [ "$5" = "-o" ]; then
  if [ -f "${BOOTSTRAP_TEST_CHILD_APP_STATE_FILE:?}" ]; then
    poll_count="$(cat "${BOOTSTRAP_TEST_CHILD_APP_POLL_COUNT_FILE:?}")"
    poll_count=$((poll_count + 1))
    printf '%s\n' "${poll_count}" > "${BOOTSTRAP_TEST_CHILD_APP_POLL_COUNT_FILE:?}"

    if [ "${poll_count}" -ge 3 ]; then
      rm -f "${BOOTSTRAP_TEST_CHILD_APP_STATE_FILE:?}"
      exit 0
    fi

    printf 'alloy|app-of-apps:argoproj.io/Application:argocd/alloy\n'
    printf 'argocd|app-of-apps:argoproj.io/Application:argocd/argocd\n'
  fi
  exit 0
fi

if [ "$#" -ge 6 ] && [ "$1" = "delete" ] && [ "$2" = "application.argoproj.io/alloy" ] && [ "$3" = "-n" ] && [ "$4" = "argocd" ]; then
  exit 0
fi

if [ "$#" -ge 6 ] && [ "$1" = "delete" ] && [ "$2" = "application.argoproj.io/argocd" ] && [ "$3" = "-n" ] && [ "$4" = "argocd" ]; then
  exit 0
fi

if [ "$#" -ge 6 ] && [ "$1" = "patch" ] && [ "$3" = "-n" ] && [ "$4" = "argocd" ] && [ "$5" = "--type=merge" ]; then
  echo "unexpected child application finalizer patch: $*" >&2
  exit 1
fi

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ] && [ "$3" = "alloy" ]; then
  if [ ! -f "${BOOTSTRAP_TEST_NAMESPACE_STATE_FILE:?}" ]; then
    exit 1
  fi

  if [ ! -f "${BOOTSTRAP_TEST_CHILD_APP_STATE_FILE:?}" ] && [ ! -f "${BOOTSTRAP_TEST_DEPLOYMENT_STATE_FILE:?}" ] && [ ! -f "${BOOTSTRAP_TEST_ALLOY_STATE_FILE:?}" ]; then
    rm -f "${BOOTSTRAP_TEST_NAMESPACE_STATE_FILE:?}"
    exit 1
  fi

  if [ "$#" -ge 5 ] && [ "$4" = "-o" ]; then
    printf '2026-03-29T01:00:00Z'
  fi
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "get" ] && [ "$2" = "namespace" ]; then
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
printf 'present\n' > "${CHILD_APP_STATE_FILE}"
printf '0\n' > "${CHILD_APP_POLL_COUNT_FILE}"

BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" \
BOOTSTRAP_TEST_DEPLOYMENT_STATE_FILE="${DEPLOYMENT_STATE_FILE}" \
BOOTSTRAP_TEST_ALLOY_STATE_FILE="${ALLOY_STATE_FILE}" \
BOOTSTRAP_TEST_NAMESPACE_STATE_FILE="${NAMESPACE_STATE_FILE}" \
BOOTSTRAP_TEST_CHILD_APP_STATE_FILE="${CHILD_APP_STATE_FILE}" \
BOOTSTRAP_TEST_CHILD_APP_POLL_COUNT_FILE="${CHILD_APP_POLL_COUNT_FILE}" \
PATH="${WORKDIR}:${PATH}" \
bash -c '
  set -euo pipefail
  source "$1"
  configure_profile local-test-plus
  require_profile_settings
  remove_argocd_app
' -- "${SCRIPT}"

if ! rg -q '^delete -f .*/cluster/local-test-plus/app-of-apps.yaml --ignore-not-found=true$' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should delete the tracked local-test-plus app-of-apps manifest"
  exit 1
fi

if ! rg -q '^get applications\.argoproj\.io -n argocd -o jsonpath=' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should discover child Argo CD applications from the tracking annotation"
  exit 1
fi

if ! rg -q '^delete application\.argoproj\.io/alloy -n argocd --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should delete discovered child Argo CD applications before waiting on workload namespaces"
  exit 1
fi

if rg -q '^delete application\.argoproj\.io/argocd -n argocd --ignore-not-found=true --wait=false$' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should not delete the self-hosted argocd child application before control-plane uninstall"
  exit 1
fi

if rg -q '^patch application\.argoproj\.io/(alloy|argocd) -n argocd --type=merge -p \{"metadata":\{"finalizers":\[\]\}\}$' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should not clear child application finalizers during the normal prune path"
  exit 1
fi

if ! rg -q '^get namespace alloy$' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should wait for the alloy namespace to be deleted"
  exit 1
fi

if ! rg -q '^patch deployment\.apps/grafana-k8s-monitoring-alloy-operator -n alloy --type=merge -p \{"metadata":\{"finalizers":\[\]\}\}$' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should clear lingering alloy operator deployment finalizers while waiting for namespace cleanup"
  exit 1
fi

if ! rg -q '^patch alloys\.collectors\.grafana\.com/grafana-k8s-monitoring-alloy-logs -n alloy --type=merge -p \{"metadata":\{"finalizers":\[\]\}\}$' "${LOG_FILE}"; then
  echo "FAIL: remove_argocd_app should clear lingering Alloy custom resource finalizers while waiting for namespace cleanup"
  exit 1
fi

echo "PASS: bootstrap remove-argocd-app profile namespace cleanup checks passed"
