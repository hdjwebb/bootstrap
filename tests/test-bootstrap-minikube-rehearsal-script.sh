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
assert_contains 'kubectl wait --for=condition=Ready node --all' "rehearsal script should wait for the cluster to be ready"
assert_contains 'kubectl -n argocd get applications' "rehearsal script should verify Argo applications"
assert_contains 'kubectl -n argocd describe applications' "rehearsal script should dump Argo application descriptions on failure"
assert_contains 'kubectl get externalsecret -A' "rehearsal script should dump ExternalSecret state on failure"
assert_contains 'kubectl describe pod' "rehearsal script should dump pod descriptions on failure"
assert_contains 'kubectl logs' "rehearsal script should dump logs on failure"

echo "PASS: bootstrap minikube rehearsal script checks passed"
