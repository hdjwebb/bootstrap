#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"
WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/security.log"

cleanup() {
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

cat <<'EOF' > "${WORKDIR}/uname"
#!/usr/bin/env bash
printf 'Darwin\n'
EOF

cat <<'EOF' > "${WORKDIR}/security"
#!/usr/bin/env bash

set -euo pipefail

printf '%s\n' "$*" >> "${BOOTSTRAP_TEST_LOG_FILE:?}"

case "$*" in
  *" -s akeyless-access-id "*)
    printf 'access-id-from-keychain'
    ;;
  *" -s akeyless-access-key "*)
    printf 'access-key-from-keychain'
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "${WORKDIR}/uname" "${WORKDIR}/security"

output="$(
  BOOTSTRAP_TEST_LOG_FILE="${LOG_FILE}" PATH="${WORKDIR}:${PATH}" bash -c '
    set -euo pipefail
    source "$1"
    unset AKEYLESS_ACCESS_ID
    unset AKEYLESS_ACCESS_SECRET_KEY
    validate_variables
    printf "ID=%s\nKEY=%s\n" "$AKEYLESS_ACCESS_ID" "$AKEYLESS_ACCESS_SECRET_KEY"
  ' -- "${SCRIPT}"
)"

if ! printf '%s\n' "${output}" | rg -q '^ID=access-id-from-keychain$'; then
  echo "FAIL: validate_variables should load AKEYLESS_ACCESS_ID from Keychain when unset"
  exit 1
fi

if ! printf '%s\n' "${output}" | rg -q '^KEY=access-key-from-keychain$'; then
  echo "FAIL: validate_variables should load AKEYLESS_ACCESS_SECRET_KEY from Keychain when unset"
  exit 1
fi

if ! rg -q 'akeyless-access-id' "${LOG_FILE}" || ! rg -q 'akeyless-access-key' "${LOG_FILE}"; then
  echo "FAIL: validate_variables should query both Keychain services"
  exit 1
fi

echo "PASS: bootstrap Keychain loading checks passed"
