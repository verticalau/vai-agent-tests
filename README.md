# Vertical AI agent tests

A GitHub Action that runs a Vertical AI agent's test scenarios and fails the
job when too few pass. It runs the [`vai` CLI](https://www.npmjs.com/package/@verticalai.com.au/vai)
(`vai test --json`), so a run passes or fails by the same verdict the app
shows: the scenario's own criteria, then any critical call check that failed
the run, then any verdict an operator set by hand.

```yaml
name: Agent tests
on: pull_request

jobs:
  agent-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - uses: verticalau/vai-agent-tests@v1
        with:
          vai_token: ${{ secrets.VAI_TOKEN }}
          agent: acme/support
          fail_under: "0.9"
          max_spend: "10"
```

Make the token in the app under **Settings > API tokens**, with **Edit**
access and pinned to the agent's workspace, and store it as the repository
secret `VAI_TOKEN`. The action hands it to the CLI in the
environment, never on a command line.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `vai_token` | required | A personal access token (`vai_pat_…`) |
| `agent` | required | `workspace-slug/agent-slug` |
| `only` | | Scenario names or ids, one per line or comma separated. Empty runs the whole suite |
| `tags` | | Run the scenarios carrying any of these tags |
| `folder` | | Run the scenarios in this folder |
| `runs` | | Runs per scenario. Empty runs a selection once and the whole suite three times |
| `fail_under` | `1` | Fail when the pass rate over graded runs is below this, from 0 to 1 |
| `max_spend` | | The most a batch may cost, in Australian dollars |
| `version` | | Test this version number instead of the latest |
| `timeout_minutes` | `60` | Stop waiting after this many minutes |
| `base_url` | `https://app.verticalai.com.au` | The platform's address |
| `cli_version` | `1` | The `@verticalai.com.au/vai` version or range to run |

## Spend

Voice tests and large suites cost money, so the platform asks before it starts
them. Set `max_spend`: a batch estimated at or under it starts, and one over it
starts nothing and fails the job with the estimate. With `max_spend` empty,
any batch that costs money fails the job before it starts.

## Outputs and exit status

| Output | Meaning |
| --- | --- |
| `pass_rate` | Passed runs over graded runs, from 0 to 1 |
| `passed`, `graded` | The counts behind it |
| `batch_id` | The batch, to read again with `vai run get_test_results` |

The step passes when the pass rate meets `fail_under`, fails with exit code 1
when it does not, and fails with exit code 2 when the tests could not run (a
bad token, an unknown scenario, a batch over `max_spend`). Runs the test
harness dropped are reported and not counted, and a batch that was cut off
fails. The job summary lists every scenario with its verdict.

The full guide is at
[docs.verticalai.com.au/docs/platform/eval-gate](https://docs.verticalai.com.au/docs/platform/eval-gate).

## Developing the action

`run.test.sh` runs `run.sh` against a fake CLI and checks the arguments,
outputs, summary and exit codes:

```bash
bash run.test.sh
```

Set `VAI_BIN` to run a local build instead of the published package, for
example `VAI_BIN="node /path/to/vai-cli/dist/vai.js"`.
