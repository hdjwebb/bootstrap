#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/scripts/rehearse-minikube-local-test-plus.sh"

timeout_output="$(
  BOOTSTRAP_REHEARSAL_EXPECTED_APPS_TIMEOUT=615 bash -c '
    set -euo pipefail
    source "$1"

    call_count_file="$(mktemp)"
    printf "0" > "${call_count_file}"

    kubectl() {
      case "$*" in
        "-n argocd get applications")
          call_count="$(cat "${call_count_file}")"
          call_count=$((call_count + 1))
          printf "%s" "${call_count}" > "${call_count_file}"
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

if ! printf '%s\n' "${timeout_output}" | rg -q '^⏳   local-test-plus applications still waiting \(0s/615s\): missing=monitoring\(OutOfSync/Progressing\)$'; then
  echo "FAIL: rehearsal script should honor BOOTSTRAP_REHEARSAL_EXPECTED_APPS_TIMEOUT in its heartbeats"
  exit 1
fi

echo "PASS: bootstrap rehearsal timeout config checks passed"
