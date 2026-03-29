#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"

assert_contains() {
  local pattern="$1"
  local message="$2"

  if ! rg -q --fixed-strings "$pattern" "${SCRIPT}"; then
    echo "FAIL: ${message}"
    exit 1
  fi
}

assert_contains "https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.6/manifests/install.yaml" \
  "bootstrap.sh should pin Argo CD to v3.3.6"

assert_contains "https://github.com/cert-manager/cert-manager/releases/download/v1.20.1/cert-manager.yaml" \
  "bootstrap.sh should pin cert-manager to v1.20.1 for install/uninstall"

assert_contains "https://github.com/envoyproxy/gateway/releases/download/v1.7.1/install.yaml" \
  "bootstrap.sh should pin Envoy Gateway to v1.7.1"

assert_contains "https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml" \
  "bootstrap.sh should pin MetalLB to v0.15.3"

echo "PASS: bootstrap upstream version pin checks passed"
