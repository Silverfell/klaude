# Verification

Run the deterministic regression suite from the checkout:

```bash
# bash -n takes one script; everything after the first is an argument to it.
for f in setup.sh upgrade.sh template/check-log.sh tests/verify.sh; do
  /bin/bash -n "$f" || echo "SYNTAX ERROR in $f"
done
/bin/bash tests/verify.sh
```

It requires Bash, Git, the SQLite CLI and standard Unix utilities. It builds
temporary projects, runs the real installers, compares every upgraded schema
with a fresh database, executes complete SQL examples (including heredocs), and
injects backup/removal failures. It also covers archive collisions, contract hard
links, altered trigger/view definitions, objects the shipped schema does not
define, immutable rows, nullable references, literal shell metacharacters in
authored log text, and the syntax of every shipped script. It makes no model calls.

## Live session evaluations

```bash
python3 tests/session_eval.py
python3 tests/session_eval.py --case consent --timeout 240
python3 tests/session_eval.py --case interrupted --case consent
python3 tests/session_eval.py --output-dir /tmp/klawde-evaluation
```

These are opt-in evaluations using Python 3 and an installed, authenticated Codex
CLI. They use the CLI's default model and normal workspace-write sandbox, with
approval requests disabled. User config and execution rules are excluded for
reproducibility; login credentials still come from the existing Codex runtime.
Model calls require network access and consume the account's normal usage.
Codex manages its own session storage as usual so follow-up turns can resume the
same conversation. There is no bypass of the agent's sandbox.

Each scenario installs the generated Codex layout into a disposable project,
initializes a local Git baseline, and interacts with the actual agent. The test
process checks resulting database rows, file contents, measurements and response
blocks. It never substitutes a simulated agent or an implementation of the
protocol for the real conversation.

| Scenario | Required behavior |
| --- | --- |
| `entry` | Ask for missing purpose/scope, wait, initialize once, avoid example-area leakage, and leave records unchanged on repeated entry. |
| `close` | Preserve literal backticks, `$()`, dollar signs, quotes and apostrophes in a decision; execute none of them; keep user fields intact; avoid duplicate writes at a second checkpoint. |
| `authoring` | Refuse a bare fact as a concern unless completed into three parts, and keep a change with no project-level meaning out of the permanent log. |
| `interrupted` | Detect a scope change logged before an interrupted close, stop entry, reconcile only after the user authorizes it, and avoid logging the same scope change again. |
| `consent` | Wait before promotion, reject ambiguous batch approval, apply a specifically approved question exactly, and honor a keep-open disposition. |
| `shape` | Restore an oversized maintained field while preserving declined user-field reshapes and extra content; paste the actual measured shape. |

Every turn also checks that the protected fixture file survives and the agent
neither stages nor commits changes. Every successful scenario finishes by running
the installed schema checker.

Fixtures, prompts, final responses, JSONL events, stderr and `results.json` are
retained in the printed artifact directory. An explicit output directory must
not already exist. A timeout, runtime failure or failed assertion fails the
evaluation; unavailable model access never counts as a pass. The default timeout
is 240 seconds per turn and can be adjusted with `--timeout`.
An account or runtime error stops the run; later scenarios are marked `not_run`
instead of repeatedly calling an unavailable service. Rerun those cases after
access is restored.

These evaluations exercise Codex's installed skills. The shell suite verifies
both installation layouts; live Claude Code behavior is not covered by this
runner. Results are model-dependent, so report the actual scenarios and artifacts
run rather than treating a single pass as a universal guarantee.
