#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_SCRIPT="${BOOTSTRAP_REHEARSAL_BOOTSTRAP_SCRIPT:-${REPO_ROOT}/bootstrap.sh}"
CYCLES="${BOOTSTRAP_REHEARSAL_CYCLES:-1}"
MINIKUBE_PROFILE="${BOOTSTRAP_MINIKUBE_PROFILE:-minikube}"
REHEARSAL_LOCK_DIR="${BOOTSTRAP_REHEARSAL_LOCK_DIR:-${TMPDIR:-/tmp}/bootstrap-rehearsal-${MINIKUBE_PROFILE}.lock}"

log_step() {
  echo "==> $*"
}

log_wait_heartbeat() {
  local description="$1"
  local elapsed="$2"
  local timeout="$3"
  local resource_hint="${4:-}"

  if [ -n "${resource_hint}" ]; then
    echo "⏳   ${description} still waiting (${elapsed}s/${timeout}s): ${resource_hint}" >&2
  else
    echo "⏳   ${description} still waiting (${elapsed}s/${timeout}s)" >&2
  fi
}

wait_for_predicate_with_heartbeat() {
  local description="$1"
  local timeout="${2:-300}"
  local interval="${3:-5}"
  local resource_hint="${4:-}"
  local elapsed=0

  shift 4

  while true; do
    if "$@"; then
      return 0
    fi

    if [ "${elapsed}" -ge "${timeout}" ]; then
      echo "❌   Error: ${description} was not ready within ${timeout}s." >&2
      return 1
    fi

    log_wait_heartbeat "${description}" "${elapsed}" "${timeout}" "${resource_hint}"
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done
}

acquire_rehearsal_lock() {
  local lock_pid_file="${REHEARSAL_LOCK_DIR}/pid"
  local lock_owner=""

  while true; do
    if mkdir "${REHEARSAL_LOCK_DIR}" 2>/dev/null; then
      printf '%s\n' "$$" > "${lock_pid_file}"
      trap release_rehearsal_lock EXIT INT TERM
      echo "Acquired rehearsal lock: ${REHEARSAL_LOCK_DIR}"
      return 0
    fi

    if [ -f "${lock_pid_file}" ]; then
      lock_owner="$(cat "${lock_pid_file}" 2>/dev/null || true)"
      if [ -n "${lock_owner}" ] && kill -0 "${lock_owner}" 2>/dev/null; then
        echo "❌   Error: another rehearsal is already running for profile ${MINIKUBE_PROFILE} (pid ${lock_owner})." >&2
        return 1
      fi
    fi

    rm -rf "${REHEARSAL_LOCK_DIR}"
  done
}

release_rehearsal_lock() {
  if [ -d "${REHEARSAL_LOCK_DIR}" ]; then
    rm -rf "${REHEARSAL_LOCK_DIR}"
  fi
}

wait_for_cluster_ready() {
  wait_for_predicate_with_heartbeat \
    "Kubernetes nodes to be Ready" \
    180 \
    5 \
    "context=${MINIKUBE_PROFILE}" \
    cluster_nodes_are_ready
}

wait_for_namespace_deleted() {
  local namespace="$1"
  local timeout="${2:-180}"
  wait_for_predicate_with_heartbeat \
    "namespace ${namespace} to be deleted" \
    "${timeout}" \
    5 \
    "namespace=${namespace}" \
    namespace_is_deleted "${namespace}"
}

wait_for_crd_deleted() {
  local crd_name="$1"
  local timeout="${2:-180}"
  wait_for_predicate_with_heartbeat \
    "CRD ${crd_name} to be deleted" \
    "${timeout}" \
    5 \
    "crd=${crd_name}" \
    crd_is_deleted "${crd_name}"
}

namespace_is_deleted() {
  local namespace="$1"

  ! kubectl get namespace "${namespace}" >/dev/null 2>&1
}

crd_is_deleted() {
  local crd_name="$1"

  ! kubectl get crd "${crd_name}" >/dev/null 2>&1
}

cluster_nodes_are_ready() {
  local total_nodes=""
  local ready_nodes=""

  total_nodes="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  ready_nodes="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {count++} END {print count+0}')"

  [ -n "${total_nodes}" ] && [ "${total_nodes}" -gt 0 ] && [ "${total_nodes}" = "${ready_nodes}" ]
}

load_akeyless_credentials() {
  if [ -n "${AKEYLESS_ACCESS_ID:-}" ] && [ -n "${AKEYLESS_ACCESS_SECRET_KEY:-}" ]; then
    return 0
  fi

  if [ "$(uname -s)" != "Darwin" ] || ! command -v security >/dev/null 2>&1; then
    return 0
  fi

  export AKEYLESS_ACCESS_ID="${AKEYLESS_ACCESS_ID:-$(security find-generic-password -a "${USER}" -s akeyless-access-id -w 2>/dev/null || true)}"
  export AKEYLESS_ACCESS_SECRET_KEY="${AKEYLESS_ACCESS_SECRET_KEY:-$(security find-generic-password -a "${USER}" -s akeyless-access-key -w 2>/dev/null || true)}"
}

dump_failure_state() {
  echo "--- cluster info ---"
  kubectl config current-context || true
  kubectl get nodes -o wide || true

  echo "--- applications ---"
  kubectl -n argocd get applications || true
  kubectl -n argocd describe applications || true

  echo "--- externalsecrets ---"
  kubectl get externalsecret -A || true

  echo "--- pods ---"
  kubectl get pods -A || true

  while IFS= read -r pod_line; do
    namespace="$(printf '%s\n' "${pod_line}" | awk '{print $1}')"
    pod_name="$(printf '%s\n' "${pod_line}" | awk '{print $2}')"

    echo "--- describe ${namespace}/${pod_name} ---"
    kubectl describe pod "${pod_name}" -n "${namespace}" || true

    echo "--- logs ${namespace}/${pod_name} ---"
    kubectl logs "${pod_name}" -n "${namespace}" --all-containers --tail=200 || true
  done < <(kubectl get pods -A --no-headers | awk '$4 != "Running" || $3 !~ /^[0-9]+\/[0-9]+$/ || $2 == "" {print $0}')
}

wait_for_expected_apps() {
  local timeout=300
  local elapsed=0
  local apps_output=""
  local missing_apps=""

  while true; do
    apps_output="$(kubectl -n argocd get applications 2>/dev/null || true)"
    if expected_apps_are_ready "${apps_output}"; then
      printf '%s\n' "${apps_output}"
      return 0
    fi
    missing_apps="${EXPECTED_APPS_MISSING:-unknown}"

    if [ "${elapsed}" -ge "${timeout}" ]; then
      printf '%s\n' "${apps_output}" >&2
      return 1
    fi

    log_wait_heartbeat "local-test-plus applications" "${elapsed}" "${timeout}" "missing=${missing_apps}"
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

expected_apps_are_ready() {
  local apps_output="$1"
  local name=""
  local sync_status=""
  local health_status=""
  local missing_list=()

  EXPECTED_APPS_MISSING=""

  if [ -z "${apps_output}" ]; then
    EXPECTED_APPS_MISSING="applications output unavailable"
    return 1
  fi

  while read -r name sync_status health_status _; do
    [ -z "${name}" ] && continue
    [ "${name}" = "NAME" ] && continue

    if ! expected_app_is_healthy "${name}" "${sync_status}" "${health_status}"; then
      missing_list+=("${name}(${sync_status}/${health_status})")
    fi
  done <<< "${apps_output}"

  if [ "${#missing_list[@]}" -eq 0 ]; then
    return 0
  fi

  EXPECTED_APPS_MISSING="$(printf '%s, ' "${missing_list[@]}")"
  EXPECTED_APPS_MISSING="${EXPECTED_APPS_MISSING%, }"
  return 1
}

expected_app_is_healthy() {
  local name="$1"
  local sync_status="$2"
  local health_status="$3"

  case "${name}" in
    alloy|app-of-apps|argocd|cert-manager|cnpg|envoy|metallb|metrics-server|monitoring)
      [ "${sync_status}" = "Synced" ] && [ "${health_status}" = "Healthy" ]
      ;;
    *)
      return 1
      ;;
  esac
}

verify_stack_removed() {
  local namespace
  local crd_name

  for namespace in argocd cert-manager external-secrets; do
    echo "Waiting for namespace ${namespace} to be deleted..."
    wait_for_namespace_deleted "${namespace}" 180
  done

  for crd_name in applications.argoproj.io externalsecrets.external-secrets.io clustersecretstores.external-secrets.io clusterissuers.cert-manager.io; do
    echo "Waiting for CRD ${crd_name} to be deleted..."
    wait_for_crd_deleted "${crd_name}" 180
  done
}

main() {
  local cycle

  load_akeyless_credentials
  acquire_rehearsal_lock

  for cycle in $(seq 1 "${CYCLES}"); do
    log_step "Cycle ${cycle}/${CYCLES}: minikube delete"
    minikube delete -p "${MINIKUBE_PROFILE}"

    log_step "Cycle ${cycle}/${CYCLES}: minikube start"
    minikube start -p "${MINIKUBE_PROFILE}"

    log_step "Cycle ${cycle}/${CYCLES}: wait for cluster"
    kubectl config use-context "${MINIKUBE_PROFILE}" >/dev/null 2>&1 || true
    wait_for_cluster_ready

    log_step "Cycle ${cycle}/${CYCLES}: bootstrap full-install"
    if ! bash "${BOOTSTRAP_SCRIPT}" --profile local-test-plus full-install; then
      dump_failure_state
      exit 1
    fi

    log_step "Cycle ${cycle}/${CYCLES}: verify applications"
    if ! wait_for_expected_apps; then
      dump_failure_state
      exit 1
    fi

    log_step "Cycle ${cycle}/${CYCLES}: bootstrap full-uninstall"
    if ! bash "${BOOTSTRAP_SCRIPT}" --profile local-test-plus full-uninstall; then
      dump_failure_state
      exit 1
    fi

    log_step "Cycle ${cycle}/${CYCLES}: verify uninstall cleanup"
    if ! verify_stack_removed; then
      dump_failure_state
      exit 1
    fi

    log_step "Cycle ${cycle}/${CYCLES}: bootstrap full-install reinstall"
    if ! bash "${BOOTSTRAP_SCRIPT}" --profile local-test-plus full-install; then
      dump_failure_state
      exit 1
    fi

    log_step "Cycle ${cycle}/${CYCLES}: verify applications after reinstall"
    if ! wait_for_expected_apps; then
      dump_failure_state
      exit 1
    fi

    kubectl -n argocd get applications
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
