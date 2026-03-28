#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/scripts/rehearse-minikube-local-test-plus.sh"

if [ ! -f "${SCRIPT}" ]; then
  echo "FAIL: rehearsal script should exist at ${SCRIPT}"
  exit 1
fi

assert_contains() {
  local pattern="$1"
  local message="$2"

  if ! rg -q -- "$pattern" "${SCRIPT}"; then
    echo "FAIL: ${message}"
    exit 1
  fi
}

assert_contains 'minikube delete' "rehearsal script should tear minikube down"
assert_contains 'minikube start' "rehearsal script should start minikube"
assert_contains '--profile local-test-plus full-install' "rehearsal script should bootstrap local-test-plus"
assert_contains '--profile local-test-plus full-uninstall' "rehearsal script should exercise full-uninstall on the live cluster"
assert_contains '^cluster_nodes_are_ready\(\)' "rehearsal script should poll node readiness with a heartbeat"
assert_contains 'kubectl -n argocd get applications' "rehearsal script should verify Argo applications"
assert_contains '^acquire_rehearsal_lock\(\)' "rehearsal script should guard against overlapping destructive runs"
assert_contains '^log_step\(\)' "rehearsal script should print structured cycle steps"
assert_contains '^expected_apps_are_ready\(\)' "rehearsal script should centralize local-test-plus app validation"
assert_contains '^expected_app_is_healthy\(\)' "rehearsal script should explicitly enumerate the required applications"
assert_contains 'alloy\|app-of-apps\|argocd\|cert-manager\|cnpg\|envoy\|metallb\|metrics-server\|monitoring' "rehearsal script should require the full disposable app set to converge"
assert_contains 'for namespace in argocd cert-manager external-secrets' "rehearsal script should verify all managed namespaces are removed after uninstall"
assert_contains 'kubectl get namespace "\$\{namespace\}"' "rehearsal script should poll namespace deletion after uninstall"
assert_contains 'kubectl -n argocd describe applications' "rehearsal script should dump Argo application descriptions on failure"
assert_contains 'kubectl get externalsecret -A' "rehearsal script should dump ExternalSecret state on failure"
assert_contains 'kubectl describe pod' "rehearsal script should dump pod descriptions on failure"
assert_contains 'kubectl logs' "rehearsal script should dump logs on failure"

install_count="$(rg -c -- '--profile local-test-plus full-install' "${SCRIPT}")"
if [ "${install_count}" -lt 2 ]; then
  echo "FAIL: rehearsal script should perform an install, uninstall, and reinstall sequence on the same cluster"
  exit 1
fi

echo "PASS: bootstrap minikube rehearsal script checks passed"
