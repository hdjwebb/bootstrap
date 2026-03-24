#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_SCRIPT="${REPO_ROOT}/bootstrap.sh"
CYCLES="${BOOTSTRAP_REHEARSAL_CYCLES:-1}"
MINIKUBE_PROFILE="${BOOTSTRAP_MINIKUBE_PROFILE:-minikube}"

wait_for_cluster_ready() {
  echo "Waiting for Kubernetes nodes to be Ready..."
  kubectl wait --for=condition=Ready node --all --timeout=180s
}

wait_for_namespace_deleted() {
  local namespace="$1"
  local timeout="${2:-180}"
  local elapsed=0

  while kubectl get namespace "${namespace}" >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${timeout}" ]; then
      echo "Namespace ${namespace} was not deleted within ${timeout}s." >&2
      return 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done
}

wait_for_crd_deleted() {
  local crd_name="$1"
  local timeout="${2:-180}"
  local elapsed=0

  while kubectl get crd "${crd_name}" >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${timeout}" ]; then
      echo "CRD ${crd_name} was not deleted within ${timeout}s." >&2
      return 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done
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
  done < <(kubectl get pods -A --no-headers | awk '$4 != "Running" || $3 !~ /^[0-9]+\\/[0-9]+$/ || $2 == "" {print $0}')
}

wait_for_expected_apps() {
  local timeout=300
  local elapsed=0
  local apps_output=""

  while true; do
    apps_output="$(kubectl -n argocd get applications 2>/dev/null || true)"

    if printf '%s\n' "${apps_output}" | rg -q '^app-of-apps[[:space:]]+Synced[[:space:]]+Healthy$' &&
       printf '%s\n' "${apps_output}" | rg -q '^argocd[[:space:]]+Synced[[:space:]]+Healthy$' &&
       printf '%s\n' "${apps_output}" | rg -q '^cert-manager[[:space:]]+Synced[[:space:]]+Healthy$' &&
       printf '%s\n' "${apps_output}" | rg -q '^metrics-server[[:space:]]+Synced[[:space:]]+Healthy$'; then
      printf '%s\n' "${apps_output}"
      return 0
    fi

    if [ "${elapsed}" -ge "${timeout}" ]; then
      printf '%s\n' "${apps_output}" >&2
      return 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done
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

  for cycle in $(seq 1 "${CYCLES}"); do
    echo "=== Cycle ${cycle}/${CYCLES}: minikube delete ==="
    minikube delete -p "${MINIKUBE_PROFILE}"

    echo "=== Cycle ${cycle}/${CYCLES}: minikube start ==="
    minikube start -p "${MINIKUBE_PROFILE}"

    echo "=== Cycle ${cycle}/${CYCLES}: wait for cluster ==="
    kubectl config use-context "${MINIKUBE_PROFILE}" >/dev/null 2>&1 || true
    wait_for_cluster_ready

    echo "=== Cycle ${cycle}/${CYCLES}: bootstrap full-install ==="
    if ! bash "${BOOTSTRAP_SCRIPT}" --profile local-test-plus full-install; then
      dump_failure_state
      exit 1
    fi

    echo "=== Cycle ${cycle}/${CYCLES}: verify applications ==="
    if ! wait_for_expected_apps; then
      dump_failure_state
      exit 1
    fi

    echo "=== Cycle ${cycle}/${CYCLES}: bootstrap full-uninstall ==="
    if ! bash "${BOOTSTRAP_SCRIPT}" --profile local-test-plus full-uninstall; then
      dump_failure_state
      exit 1
    fi

    echo "=== Cycle ${cycle}/${CYCLES}: verify uninstall cleanup ==="
    if ! verify_stack_removed; then
      dump_failure_state
      exit 1
    fi

    echo "=== Cycle ${cycle}/${CYCLES}: bootstrap full-install reinstall ==="
    if ! bash "${BOOTSTRAP_SCRIPT}" --profile local-test-plus full-install; then
      dump_failure_state
      exit 1
    fi

    echo "=== Cycle ${cycle}/${CYCLES}: verify applications after reinstall ==="
    if ! wait_for_expected_apps; then
      dump_failure_state
      exit 1
    fi

    kubectl -n argocd get applications
  done
}

main "$@"
