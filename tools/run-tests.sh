#!/usr/bin/env bash
set -Eeuo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/installer/install.sh" "$ROOT/tools/run-tests.sh"
if command -v node >/dev/null 2>&1; then node --check "$ROOT/tools/publish_frontend.js"; fi
python3 "$ROOT/tests/verify-docs-current.py"
python3 "$ROOT/tests/verify-package.py"
python3 "$ROOT/tests/verify-ha-contract.py"
python3 "$ROOT/tests/verify-system-metadata.py"
python3 "$ROOT/tests/verify-static.py"
python3 "$ROOT/tests/verify-architecture-conformance.py"
python3 "$ROOT/tests/verify-read-model-contract.py"
python3 "$ROOT/tests/verify-p24r15.py"
python3 "$ROOT/tests/verify-verification-model.py"
python3 "$ROOT/tests/test-build-flow.py"
python3 "$ROOT/tests/test-installer-db-version.py"
if command -v node >/dev/null 2>&1; then
  node "$ROOT/tests/test-runtime-functions.js"
  node "$ROOT/tests/test-p24-analysis.js"
  node "$ROOT/tests/test-archive-export.js"
  node "$ROOT/tests/test-p24-editor.js"
  node "$ROOT/tests/test-p24-methodology.js"
  node "$ROOT/tests/test-p24r7.js"
  node "$ROOT/tests/test-p24r8.js"
  node "$ROOT/tests/test-p24r9.js"
  node "$ROOT/tests/test-p24r10.js"
else
  echo "SKIP: test-runtime-functions.js krever Node på utviklingshost; dette er en releaseport og kjøres ikke av installeren."
fi

printf '%s\n' 'RESULT: PASS – complete automated release gate'
