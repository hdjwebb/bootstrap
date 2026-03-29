#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
OUTPUT_FILE="$(mktemp)"
cleanup() {
  rm -rf "${TMP_DIR}" "${OUTPUT_FILE}"
}
trap cleanup EXIT

# shellcheck source=/dev/null
source "${REPO_ROOT}/bootstrap.sh"
configure_profile local-test
write_argocd_kustomization "${TMP_DIR}"
(
  cd "${TMP_DIR}"
  kustomize build . > "${OUTPUT_FILE}"
)

REDIS_BLOCK="$(awk '
  function flush() {
    if (doc ~ /kind: Deployment/ && doc ~ /\n  name: argocd-redis\n/) {
      printf "%s", doc
      found = 1
      exit 0
    }
    doc = ""
  }
  /^---$/ { flush(); next }
  { doc = doc $0 ORS }
  END { if (!found) flush() }
' "${OUTPUT_FILE}")"

if [[ -z "${REDIS_BLOCK}" ]]; then
  echo "FAIL: bootstrap Argo render should include the argocd-redis deployment"
  exit 1
fi

if ! grep -Fq -- 'mirror.gcr.io/library/redis:8.2.3-alpine' <<<"${REDIS_BLOCK}"; then
  echo "FAIL: bootstrap Argo render should override Redis to mirror.gcr.io/library/redis:8.2.3-alpine"
  exit 1
fi

if ! grep -Fq -- 'imagePullPolicy: IfNotPresent' <<<"${REDIS_BLOCK}"; then
  echo "FAIL: bootstrap Argo render should set Redis imagePullPolicy to IfNotPresent"
  exit 1
fi

if grep -Fq -- 'public.ecr.aws/docker/library/redis:8.2.3-alpine' <<<"${REDIS_BLOCK}"; then
  echo "FAIL: bootstrap Argo render should not keep the public ECR Redis image"
  exit 1
fi

echo "PASS: bootstrap Argo Redis image override checks passed"
