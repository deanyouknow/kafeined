#!/usr/bin/env bash
# smoke-test.sh — end-to-end lifecycle test for kafeined.
# Runs on macOS, Linux, and Windows (Git Bash). No CI needed; run it manually:
#   bash skills/kafeined/scripts/smoke-test.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$SCRIPT_DIR/.."
RUNNER="$SKILL_DIR/scripts/kafeined.sh"

fail() { echo "FAIL: $*"; exit 1; }

# 1. Syntax check
bash -n "$RUNNER" || fail "kafeined.sh has a syntax error"

# 2. start must succeed and report holding
OUT="$(bash "$RUNNER" start)" || fail "start exited non-zero: $OUT"
case "$OUT" in
  *"holding machine awake"*) : ;;
  *) fail "start printed unexpected output: $OUT" ;;
esac

# 3. status must be ACTIVE and exit 0
OUT="$(bash "$RUNNER" status)" && : || fail "status exited non-zero while holding"
case "$OUT" in
  *ACTIVE*) : ;;
  *) fail "status did not report ACTIVE: $OUT" ;;
esac

# 4. double start must be idempotent
OUT="$(bash "$RUNNER" start)" || fail "second start failed: $OUT"
case "$OUT" in
  *"already active"*) : ;;
  *) fail "second start was not idempotent: $OUT" ;;
esac

# 5. renew must restart cleanly
OUT="$(bash "$RUNNER" renew)" || fail "renew failed: $OUT"
case "$OUT" in
  *"holding machine awake"*) : ;;
  *) fail "renew printed unexpected output: $OUT" ;;
esac

# 6. stop must release
OUT="$(bash "$RUNNER" stop)" || fail "stop exited non-zero: $OUT"

# 7. status must be inactive afterwards
if bash "$RUNNER" status >/dev/null 2>&1; then
  fail "status still reports ACTIVE after stop"
fi

# 8. stop again must be safe (no hold)
bash "$RUNNER" stop >/dev/null 2>&1 || fail "stop without a hold must still exit 0"

# 9. bad usage exits 2
if bash "$RUNNER" bogus >/dev/null 2>&1; then
  fail "bogus command must exit non-zero"
fi

# 10. non-integer --hours is rejected
if bash "$RUNNER" start --hours abc >/dev/null 2>&1; then
  fail "--hours abc must be rejected"
fi

# 11. while mode: successful command releases and propagates rc 0
OUT="$(bash "$RUNNER" while true)" || fail "while true failed: $OUT"
case "$OUT" in
  *"hold released"*) : ;;
  *) fail "while true did not report release: $OUT" ;;
esac
if bash "$RUNNER" status >/dev/null 2>&1; then
  fail "hold still active after while command finished"
fi

# 12. while mode: failing command still releases and propagates rc
if OUT="$(bash "$RUNNER" while false)"; then
  fail "while false must propagate a non-zero exit code: $OUT"
fi
case "$OUT" in
  *"hold released"*) : ;;
  *) fail "while false did not report release: $OUT" ;;
esac
if bash "$RUNNER" status >/dev/null 2>&1; then
  fail "hold still active after failing while command"
fi

# 13. while mode without a command is a usage error
if bash "$RUNNER" while >/dev/null 2>&1; then
  fail "while without a command must exit 2"
fi

# cleanup
rm -rf "${TMPDIR:-/tmp}/kafeined"
echo "SMOKE TEST PASS"
