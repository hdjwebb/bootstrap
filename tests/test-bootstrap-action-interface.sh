#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"

assert_contains() {
  local pattern="$1"
  local message="$2"

  if ! rg -q "$pattern" "$SCRIPT"; then
    echo "FAIL: $message"
    exit 1
  fi
}

assert_not_contains() {
  local pattern="$1"
  local message="$2"

  if rg -q "$pattern" "$SCRIPT"; then
    echo "FAIL: $message"
    exit 1
  fi
}

assert_contains '^usage\(\)' "bootstrap.sh should define a usage helper"
assert_contains '^run_action\(\)' "bootstrap.sh should dispatch named actions"
assert_contains '^run_action_sequence\(\)' "bootstrap.sh should execute actions from CLI input"
assert_contains 'case "\$action" in' "bootstrap.sh should validate actions through a case statement"
assert_contains 'full-install' "bootstrap.sh should expose an explicit full-install action"
assert_not_contains '^  add_argocd_app_of_apps$' "bootstrap.sh should not hard-code a single action inside main()"

if ! PATH="/usr/bin:/bin" bash "$SCRIPT" help >/dev/null; then
  echo "FAIL: bootstrap.sh help should work without requiring cluster access or kubectl"
  exit 1
fi

echo "PASS: bootstrap action interface checks passed"
