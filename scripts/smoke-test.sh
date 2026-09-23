#!/usr/bin/env bash
# smoke-test.sh — end-to-end lifecycle test for kafeined.
# Runs on macOS, Linux, and Windows (Git Bash). Used by CI (.github/workflows/ci.yml).

set -u
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*"; exit 1; }

# 1. Syntax check
bash -n scripts/kafeined.sh || fail "kafeined.sh has a syntax error"

# 2. start must succeed and report holding
OUT="$(bash scripts/kafeined.sh start)" || fail "start exited non-zero: $OUT"
case "$OUT" in
  *"holding machine awake"*) : ;;
  *) fail "start printed unexpected output: $OUT" ;;
esac

# 3. status must be ACTIVE and exit 0
OUT="$(bash scripts/kafeined.sh status)" && : || fail "status exited non-zero while holding"
case "$OUT" in
  *ACTIVE*) : ;;
  *) fail "status did not report ACTIVE: $OUT" ;;
esac

# 4. double start must be idempotent
OUT="$(bash scripts/kafeined.sh start)" || fail "second start failed: $OUT"
case "$OUT" in
  *"already active"*) : ;;
  *) fail "second start was not idempotent: $OUT" ;;
esac

# 5. renew must restart cleanly
OUT="$(bash scripts/kafeined.sh renew)" || fail "renew failed: $OUT"
case "$OUT" in
  *"holding machine awake"*) : ;;
  *) fail "renew printed unexpected output: $OUT" ;;
esac

# 6. stop must release
OUT="$(bash scripts/kafeined.sh stop)" || fail "stop exited non-zero: $OUT"

# 7. status must be inactive afterwards
if bash scripts/kafeined.sh status >/dev/null 2>&1; then
  fail "status still reports ACTIVE after stop"
fi

# 8. stop again must be safe (no hold)
bash scripts/kafeined.sh stop >/dev/null 2>&1 || fail "stop without a hold must still exit 0"

# 9. bad usage exits 2
if bash scripts/kafeined.sh bogus >/dev/null 2>&1; then
  fail "bogus command must exit non-zero"
fi

# 10. non-integer --hours is rejected
if bash scripts/kafeined.sh start --hours abc >/dev/null 2>&1; then
  fail "--hours abc must be rejected"
fi

# cleanup
rm -rf "${TMPDIR:-/tmp}/kafeined"
echo "SMOKE TEST PASS"
