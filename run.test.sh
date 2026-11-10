#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok() { echo "  ok: $1"; PASS=$((PASS + 1)); }
no() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

cat >"$WORK/fake-vai" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_ARGS"
printf '%s\n' "${VAI_TOKEN:-}" >"$FAKE_ARGS.token"
cat "$FAKE_OUT"
exit "${FAKE_CODE:-0}"
FAKE
chmod +x "$WORK/fake-vai"

RESULT_PASS='{"type":"result","ok":true,"batchId":"batch-1","passRate":1,"threshold":0.9,"passed":3,"graded":3,"infraFailed":0,"truncated":false,"scenarios":[{"test":"Where is my order","outcome":"passed","passed":3,"counted":3,"passRate":1,"summary":"passed, 3/3 passed"}],"failedRuns":[]}'
RESULT_FAIL='{"type":"result","ok":false,"batchId":"batch-2","passRate":0.5,"threshold":0.9,"passed":1,"graded":2,"infraFailed":1,"truncated":false,"scenarios":[{"test":"Refund | partial","outcome":"flaky","passed":1,"counted":2,"passRate":0.5,"summary":"flaky, 1/2 passed"}],"failedRuns":[]}'
NOT_RUN='{"ok":false,"error":"The estimate, A$45.00, is over --max-spend A$10.00. Nothing was started.","exitCode":2}'

gate() {
  local name="$1" code="$2" output="$3"
  shift 3
  local dir="$WORK/$name"
  mkdir -p "$dir"
  printf '%s\n' '{"type":"started","batchId":"batch-1","total":3}' "$output" >"$dir/out.jsonl"
  : >"$dir/output"
  : >"$dir/summary"
  env -i PATH="$PATH" HOME="$HOME" \
    VAI_BIN="$WORK/fake-vai" FAKE_OUT="$dir/out.jsonl" FAKE_CODE="$code" FAKE_ARGS="$dir/args" \
    RUNNER_TEMP="$dir" GITHUB_OUTPUT="$dir/output" GITHUB_STEP_SUMMARY="$dir/summary" \
    VAI_TOKEN="vai_pat_secret_value" GATE_AGENT="acme/support" GATE_FAIL_UNDER="0.9" GATE_TIMEOUT="60" \
    "$@" bash "$HERE/run.sh" >"$dir/stdout" 2>&1
  echo $? >"$dir/code"
}

echo "a passing suite"
gate pass 0 "$RESULT_PASS"
[ "$(cat "$WORK/pass/code")" = 0 ] && ok "exits 0" || no "exits 0, got $(cat "$WORK/pass/code")"
grep -qx 'pass_rate=1' "$WORK/pass/output" && ok "outputs the pass rate" || no "outputs the pass rate"
grep -qx 'batch_id=batch-1' "$WORK/pass/output" && ok "outputs the batch" || no "outputs the batch"
grep -q 'Pass rate 100% (3 of 3 graded runs) against 90%: pass.' "$WORK/pass/summary" && ok "writes the headline" || no "writes the headline"
grep -q '| ✅ Where is my order | 3/3 | passed, 3/3 passed |' "$WORK/pass/summary" && ok "writes a row per scenario" || no "writes a row per scenario"

echo "a suite below the threshold"
gate below 1 "$RESULT_FAIL"
[ "$(cat "$WORK/below/code")" = 1 ] && ok "exits 1, as vai test does" || no "exits 1, got $(cat "$WORK/below/code")"
grep -q 'against 90%: fail.' "$WORK/below/summary" && ok "says fail" || no "says fail"
grep -qF 'Refund \| partial' "$WORK/below/summary" && ok "escapes a pipe in a scenario name" || no "escapes a pipe in a scenario name"
grep -q '1 runs did not run and are not counted.' "$WORK/below/summary" && ok "reports dropped runs" || no "reports dropped runs"

echo "a batch over the spend limit"
gate over 2 "$NOT_RUN" GATE_MAX_SPEND=10
[ "$(cat "$WORK/over/code")" = 2 ] && ok "exits 2" || no "exits 2, got $(cat "$WORK/over/code")"
grep -q 'Agent tests did not run' "$WORK/over/summary" && ok "says the tests did not run" || no "says the tests did not run"
grep -qF 'over --max-spend A$10.00' "$WORK/over/summary" && ok "carries the CLI's reason" || no "carries the CLI's reason"
[ ! -s "$WORK/over/output" ] && ok "sets no outputs" || no "sets no outputs"

echo "the arguments vai receives"
gate args 0 "$RESULT_PASS" GATE_ONLY=$'Where is my order, Refund\n' GATE_TAGS=$'smoke\nmoney' GATE_FOLDER=bookings GATE_RUNS=2 GATE_VERSION=7 GATE_MAX_SPEND=12.50
expected=$'test\nacme/support\n--json\n--fail-under\n0.9\n--timeout\n60\n--only\nWhere is my order\n--only\nRefund\n--tag\nsmoke\n--tag\nmoney\n--folder\nbookings\n--runs\n2\n--version\n7\n--max-spend\n12.50'
[ "$(cat "$WORK/args/args")" = "$expected" ] && ok "passes every input as its own argument" || { no "passes every input as its own argument"; cat "$WORK/args/args"; }
grep -q 'vai_pat_secret_value' "$WORK/args/args" && no "keeps the token out of the arguments" || ok "keeps the token out of the arguments"
[ "$(cat "$WORK/args/args.token")" = "vai_pat_secret_value" ] && ok "hands the token over as VAI_TOKEN" || no "hands the token over as VAI_TOKEN"

echo "missing inputs"
gate notoken 0 "$RESULT_PASS" VAI_TOKEN=
[ "$(cat "$WORK/notoken/code")" = 2 ] && ok "refuses an empty token" || no "refuses an empty token"
[ ! -e "$WORK/notoken/args" ] && ok "runs nothing without a token" || no "runs nothing without a token"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
