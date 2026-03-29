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
assert_contains '^run_bootstrap_profile_actions\(\)' "rehearsal script should centralize bootstrap calls through a kubeconfig-aware helper"
assert_contains 'run_bootstrap_profile_actions full-install' "rehearsal script should bootstrap local-test-plus"
assert_contains 'run_bootstrap_profile_actions full-uninstall' "rehearsal script should exercise full-uninstall on the live cluster"
assert_contains '^cluster_nodes_are_ready\(\)' "rehearsal script should poll node readiness with a heartbeat"
assert_contains '^ensure_minikube_context\(\)' "rehearsal script should verify the minikube kubeconfig context before using kubectl"
assert_contains 'minikube update-context -p "\$\{MINIKUBE_PROFILE\}"' "rehearsal script should refresh the minikube kubeconfig context after each start"
assert_contains 'kubectl config current-context' "rehearsal script should verify the active kubeconfig context after update-context"
assert_contains 'REHEARSAL_KUBECONFIG=' "rehearsal script should keep a dedicated kubeconfig for the destructive rehearsal"
assert_contains 'kubectl config use-context "\$\{MINIKUBE_PROFILE\}" --kubeconfig "\$\{REHEARSAL_KUBECONFIG\}"' "rehearsal script should pin the rehearsal kubeconfig to the minikube context"
assert_contains 'KUBECONFIG="\$\{REHEARSAL_KUBECONFIG\}" bash "\$\{BOOTSTRAP_SCRIPT\}" --profile local-test-plus "\$@"' "rehearsal script should run bootstrap against the isolated rehearsal kubeconfig"
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
install_count="$(rg -c -- 'run_bootstrap_profile_actions full-install' "${SCRIPT}")"
if [ "${install_count}" -lt 2 ]; then
  echo "FAIL: rehearsal script should perform an install, uninstall, and reinstall sequence on the same cluster"
  exit 1
fi

if ! grep -Fq "kubectl get pods -A --no-headers | awk '\$4 != \"Running\" || \$3 !~ /^[0-9]+\/[0-9]+$/ || \$2 == \"\" {print \$0}'" "${SCRIPT}"; then
  echo "FAIL: rehearsal script should use a single-slash awk regex for pod readiness filtering"
  exit 1
fi

echo "PASS: bootstrap minikube rehearsal script checks passed"
