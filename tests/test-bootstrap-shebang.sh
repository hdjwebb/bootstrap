#!/usr/bin/env bash

set -euo pipefail

SCRIPT="/Users/henry/Documents/Coding/bootstrap/bootstrap.sh"

first_line="$(head -n 1 "${SCRIPT}")"

if [ "${first_line}" != "#!/usr/bin/env bash" ]; then
  echo "FAIL: bootstrap.sh should start with a bash shebang so ./bootstrap.sh runs under bash"
  exit 1
fi

echo "PASS: bootstrap shebang check passed"
