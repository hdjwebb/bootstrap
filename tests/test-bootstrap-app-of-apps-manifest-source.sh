#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"

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
      variable_name="$3"
      printf "%s" "${!variable_name-}"
    ' -- "$SCRIPT" "$profile" "$variable_name"
  )"

  if [ "$actual" != "$expected" ]; then
    echo "FAIL: expected profile ${profile} to set ${variable_name}=${expected}, got ${actual}"
    exit 1
  fi
}

ADD_APP_FUNCTION="$(sed -n '/^add_argocd_app_of_apps()/,/^remove_argocd_app()/p' "$SCRIPT")"

assert_profile_value "microk8s-prod" "APP_OF_APPS_MANIFEST_PATH" "cluster/dev/app-of-apps.yaml"
assert_profile_value "microk8s-lab" "APP_OF_APPS_MANIFEST_PATH" "cluster/lab/app-of-apps.yaml"
assert_profile_value "local-test" "APP_OF_APPS_MANIFEST_PATH" "cluster/local-test/app-of-apps.yaml"
assert_profile_value "local-test-plus" "APP_OF_APPS_MANIFEST_PATH" "cluster/local-test-plus/app-of-apps.yaml"

if ! printf '%s\n' "$ADD_APP_FUNCTION" | rg -q 'run_kubectl_with_retry apply -f "\$\{APP_OF_APPS_MANIFEST_FILE\}"'; then
  echo "FAIL: add_argocd_app_of_apps should apply a tracked manifest file directly"
  exit 1
fi

if printf '%s\n' "$ADD_APP_FUNCTION" | rg -q 'repoURL: \$\{APP_OF_APPS_REPO_URL\}'; then
  echo "FAIL: add_argocd_app_of_apps should not render inline repoURL YAML"
  exit 1
fi

echo "PASS: bootstrap app-of-apps manifest source checks passed"
