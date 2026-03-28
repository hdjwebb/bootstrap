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

assert_contains '^set -euo pipefail$' "bootstrap.sh should enable strict shell mode"
assert_contains '^trap cleanup_temp_dirs EXIT$' "bootstrap.sh should clean up temp directories on exit"
assert_contains '^require_commands\(\)' "bootstrap.sh should define a command dependency check"
assert_contains '^require_cluster_access\(\)' "bootstrap.sh should define a cluster access check"
assert_contains '^wait_for_secret\(\)' "bootstrap.sh should wait for secrets instead of sleeping blindly"
assert_contains '^wait_for_predicate_with_heartbeat\(\)' "bootstrap.sh should centralize wait heartbeats"
assert_contains '^wait_for_namespace_deletion\(\)' "bootstrap.sh should define namespace deletion waits for uninstall paths"
assert_contains '^log_wait_heartbeat\(\)' "bootstrap.sh should emit heartbeat logs while waiting"
assert_contains '^clear_namespace_resource_finalizers\(\)' "bootstrap.sh should scrub remaining resource finalizers when namespace teardown is stuck"
assert_not_contains 'sleep 10  # Wait for 10 seconds to ensure secret is available' "bootstrap.sh should not rely on a fixed sleep before reading the Argo CD domain secret"
assert_not_contains '^waiting\(\)' "bootstrap.sh should not keep the unused waiting helper"

echo "PASS: bootstrap runtime hardening checks passed"
