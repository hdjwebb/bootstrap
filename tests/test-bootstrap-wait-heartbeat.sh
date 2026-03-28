#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"

output="$(
  bash -lc '
    source "'"${SCRIPT}"'"
    COUNT=0
    fake_predicate() {
      COUNT=$((COUNT + 1))
      [ "${COUNT}" -ge 3 ]
    }
    wait_for_predicate_with_heartbeat "demo wait" 10 1 "resource=demo" fake_predicate
  ' 2>&1
)"

if ! printf '%s\n' "${output}" | rg -q 'demo wait still waiting'; then
  echo "FAIL: wait helper should emit heartbeat output while the predicate is still false"
  exit 1
fi

if ! printf '%s\n' "${output}" | rg -q 'resource=demo'; then
  echo "FAIL: wait helper should include the resource hint in heartbeat output"
  exit 1
fi

echo "PASS: bootstrap wait heartbeat checks passed"
