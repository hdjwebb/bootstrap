#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
ADD_APP_FUNCTION="$(sed -n '/^add_argocd_app_of_apps()/,/^remove_argocd_app()/p' "$SCRIPT")"

assert_not_contains() {
  local haystack="$1"
  local pattern="$2"
  local message="$3"

  if printf '%s\n' "$haystack" | rg -q -- "$pattern"; then
    echo "FAIL: $message"
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local pattern="$2"
  local message="$3"

  if ! printf '%s\n' "$haystack" | rg -q -- "$pattern"; then
    echo "FAIL: $message"
    exit 1
  fi
}

assert_not_contains "$ADD_APP_FUNCTION" 'repoURL: \$\(kubectl get secret gitlab-repo-components-secret' "bootstrap.sh should not execute a dead secret lookup inside add-app-of-apps"
assert_contains "$ADD_APP_FUNCTION" '^add_argocd_app_of_apps\(\)' "bootstrap.sh should define add_argocd_app_of_apps"
assert_contains "$ADD_APP_FUNCTION" 'kubectl apply -f "\$\{APP_OF_APPS_MANIFEST_FILE\}"' "bootstrap.sh should apply the tracked app-of-apps manifest file"
assert_not_contains "$ADD_APP_FUNCTION" 'repoURL: \$\{APP_OF_APPS_REPO_URL\}' "bootstrap.sh should not render inline app-of-apps repository YAML"

echo "PASS: bootstrap app-of-apps template checks passed"
