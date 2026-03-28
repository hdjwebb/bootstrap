#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/scripts/rehearse-minikube-local-test-plus.sh"
WORKDIR="$(mktemp -d)"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

lock_output="$(
  bash -c '
    set -euo pipefail
    export BOOTSTRAP_REHEARSAL_LOCK_DIR="$1"
    source "$2"

    acquire_rehearsal_lock
    if acquire_rehearsal_lock; then
      echo "FAIL: second lock acquisition should not succeed"
      exit 1
    fi
  ' -- "${WORKDIR}/lock" "${SCRIPT}" 2>&1
)"

if ! printf '%s\n' "${lock_output}" | rg -q '^Acquired rehearsal lock: '; then
  echo "FAIL: rehearsal script should announce lock acquisition"
  exit 1
fi

if ! printf '%s\n' "${lock_output}" | rg -q 'another rehearsal is already running for profile'; then
  echo "FAIL: rehearsal script should reject overlapping destructive runs"
  exit 1
fi

heartbeat_output="$(
  bash -c '
    set -euo pipefail
    source "$1"

    call_count_file="$(mktemp)"
    printf '0' > "${call_count_file}"

    kubectl() {
      case "$*" in
        "-n argocd get applications")
          call_count="$(cat "${call_count_file}")"
          call_count=$((call_count + 1))
          printf '%s' "${call_count}" > "${call_count_file}"
          if [ "${call_count}" -lt 2 ]; then
            cat <<EOF
NAME             SYNC STATUS   HEALTH STATUS
alloy            Synced        Healthy
app-of-apps      Synced        Healthy
argocd           Synced        Healthy
cert-manager     Synced        Healthy
cnpg             Synced        Healthy
envoy            Synced        Healthy
metallb          Synced        Healthy
metrics-server   Synced        Healthy
monitoring       OutOfSync     Progressing
EOF
          else
            cat <<EOF
NAME             SYNC STATUS   HEALTH STATUS
alloy            Synced        Healthy
app-of-apps      Synced        Healthy
argocd           Synced        Healthy
cert-manager     Synced        Healthy
cnpg             Synced        Healthy
envoy            Synced        Healthy
metallb          Synced        Healthy
metrics-server   Synced        Healthy
monitoring       Synced        Healthy
EOF
          fi
          return 0
          ;;
        *)
          echo "unexpected kubectl call: $*" >&2
          return 1
          ;;
      esac
    }

    sleep() {
      :
    }

    wait_for_expected_apps
    rm -f "${call_count_file}"
  ' -- "${SCRIPT}" 2>&1
)"

if ! printf '%s\n' "${heartbeat_output}" | rg -q '^⏳   local-test-plus applications still waiting \(0s/300s\): missing=monitoring\(OutOfSync/Progressing\)$'; then
  echo "FAIL: rehearsal script should emit a heartbeat while waiting for the expected app set"
  exit 1
fi

echo "PASS: bootstrap rehearsal feedback checks passed"
