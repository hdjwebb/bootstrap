#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"

assert_contains() {
  local pattern="$1"
  local message="$2"

  if ! rg -q -- "$pattern" "$SCRIPT"; then
    echo "FAIL: $message"
    exit 1
  fi
}

assert_profile_value() {
  local profile="$1"
  local variable_name="$2"
  local expected="$3"
  local actual

  actual="$(
    bash -c '
      set -euo pipefail
      source "$1"
      configure_profile "$2"
      printf "%s" "${!3}"
    ' -- "$SCRIPT" "$profile" "$variable_name"
  )"

  if [ "$actual" != "$expected" ]; then
    echo "FAIL: expected profile ${profile} to set ${variable_name}=${expected}, got ${actual}"
    exit 1
  fi
}

assert_contains '^configure_profile\(\)' "bootstrap.sh should define a profile configuration helper"
assert_contains '--profile <name>' "bootstrap.sh should document the profile flag"
assert_contains 'microk8s-prod' "bootstrap.sh should expose the microk8s-prod profile"
assert_contains 'microk8s-lab' "bootstrap.sh should expose the microk8s-lab profile"
assert_contains 'local-test' "bootstrap.sh should expose the local-test profile"

assert_profile_value "microk8s-prod" "ARGOCD_ACCESS_MODE" "gateway"
assert_profile_value "microk8s-prod" "DOMAIN_SECRET_REMOTE_KEY" "/microk8s/domain"
assert_profile_value "microk8s-prod" "METALLB_ADDRESS_POOL" "192.168.0.220-192.168.0.229"

assert_profile_value "microk8s-lab" "ARGOCD_ACCESS_MODE" "gateway"
assert_profile_value "microk8s-lab" "DOMAIN_SECRET_REMOTE_KEY" "/microk8s-lab/domain"
assert_profile_value "microk8s-lab" "METALLB_ADDRESS_POOL" "192.168.0.230-192.168.0.239"

assert_profile_value "local-test" "ARGOCD_ACCESS_MODE" "port-forward"
assert_profile_value "local-test" "INSTALL_ENVOY" "false"
assert_profile_value "local-test" "INSTALL_METALLB" "false"

echo "PASS: bootstrap profile support checks passed"
