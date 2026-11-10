#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 2
}

[ -n "${VAI_TOKEN:-}" ] || fail "vai_token is empty. Pass a personal access token from a secret."
[ -n "${GATE_AGENT:-}" ] || fail "agent is empty. Pass it as workspace-slug/agent-slug."
command -v node >/dev/null || fail "Node is not on PATH. Add actions/setup-node with node-version 20 before this step."
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)' \
  || fail "vai needs Node 20 or later; this runner has $(node --version)."

args=(test "$GATE_AGENT" --json --fail-under "${GATE_FAIL_UNDER:-1}" --timeout "${GATE_TIMEOUT:-60}")

add_list() {
  local flag="$1" raw="$2" item
  while IFS= read -r item; do
    item="$(printf '%s' "$item" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -n "$item" ]; then
      args+=("$flag" "$item")
    fi
  done < <(printf '%s\n' "$raw" | tr ',' '\n')
}

add_list --only "${GATE_ONLY:-}"
add_list --tag "${GATE_TAGS:-}"
if [ -n "${GATE_FOLDER:-}" ]; then args+=(--folder "$GATE_FOLDER"); fi
if [ -n "${GATE_RUNS:-}" ]; then args+=(--runs "$GATE_RUNS"); fi
if [ -n "${GATE_VERSION:-}" ]; then args+=(--version "$GATE_VERSION"); fi
if [ -n "${GATE_MAX_SPEND:-}" ]; then args+=(--max-spend "$GATE_MAX_SPEND"); fi

if [ -n "${VAI_BIN:-}" ]; then
  read -r -a cli <<<"$VAI_BIN"
else
  cli=(npx --yes "@verticalai.com.au/vai@${GATE_CLI_VERSION:-1}")
fi

out="${RUNNER_TEMP:-$(mktemp -d)}/vai-test-result.jsonl"
set +e
"${cli[@]}" "${args[@]}" >"$out"
code=$?
set -e
cat "$out"

node - "$out" <<'NODE'
const fs = require("fs");
const lines = fs.readFileSync(process.argv[2], "utf8").split("\n").filter(Boolean);
const parsed = lines.flatMap((line) => {
  try {
    return [JSON.parse(line)];
  } catch {
    return [];
  }
});
const result = [...parsed].reverse().find((line) => line.type === "result");
const failure = parsed.find((line) => line.ok === false && typeof line.error === "string");
const append = (file, text) => file && fs.appendFileSync(file, text);
const pct = (rate) => `${Math.round(rate * 100)}%`;
const marks = { passed: "✅", failed: "❌", flaky: "⚠️", inconclusive: "❔" };
const cell = (text) => String(text).replace(/\|/g, "\\|");
if (!result) {
  append(process.env.GITHUB_STEP_SUMMARY, `### Agent tests did not run\n\n${failure ? failure.error : "vai printed no result."}\n`);
  process.exit(0);
}
append(
  process.env.GITHUB_OUTPUT,
  [`pass_rate=${result.passRate ?? ""}`, `passed=${result.passed}`, `graded=${result.graded}`, `batch_id=${result.batchId}`, ""].join("\n"),
);
const headline =
  result.passRate === null
    ? "No run was graded, so nothing was proved."
    : `Pass rate ${pct(result.passRate)} (${result.passed} of ${result.graded} graded runs) against ${pct(result.threshold)}: ${result.ok ? "pass" : "fail"}.`;
append(
  process.env.GITHUB_STEP_SUMMARY,
  [
    `### Agent tests: ${process.env.GATE_AGENT}`,
    "",
    headline,
    "",
    "| Scenario | Passed | Verdict |",
    "| --- | --- | --- |",
    ...result.scenarios.map((s) => `| ${marks[s.outcome] ?? "❔"} ${cell(s.test)} | ${s.passed}/${s.counted} | ${cell(s.summary)} |`),
    "",
    result.infraFailed > 0 ? `${result.infraFailed} runs did not run and are not counted.\n` : "",
    result.truncated ? "The batch was cut off before it finished, so it fails.\n" : "",
  ].join("\n"),
);
NODE

exit "$code"
