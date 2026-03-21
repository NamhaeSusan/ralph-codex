# Ralph Self-Improvement Loop Design

## Goal

Build a local, long-running meta loop that improves `ralph-codex` itself.
The loop must optimize for one outcome first: higher completion rates on a
small in-repo benchmark suite. It may automatically modify the entire
repository, commit the result, push a branch, and open a PR, but only when the
candidate shows an improved benchmark completion rate with zero regressions.

## Non-Goals

- CI scheduling or GitHub Actions execution
- External benchmark repositories
- Multi-model orchestration
- Parallel candidate search
- Using long-term run history as candidate prompt input

## Constraints

- Both candidate generation and review use Codex.
- Candidate generation and review use the same Codex model; only prompts differ.
- Benchmarks live inside this repository under `benchmarks/`.
- Benchmarks are fixture Git repositories with checked-in inputs.
- The loop runs locally for long sessions.
- Promotion requires:
  - benchmark completion rate strictly better than baseline
  - zero benchmark regressions
  - reviewer Codex decision of `approve`

## High-Level Architecture

The loop is split into six components.

### `benchmarks/`

Contains self-contained benchmark cases. Each case includes:

- a small fixture Git repository
- a checked-in `.codex-ralph/prd.json`
- metadata describing how to initialize, run, and verify the case

The benchmark suite is the source of truth for measuring whether `ralph-codex`
actually improved.

### `loop/runner`

Top-level orchestrator for one full self-improvement iteration. It coordinates:

1. baseline measurement
2. candidate branch creation
3. candidate generation with Codex
4. full benchmark reevaluation
5. reviewer decision
6. promotion or rejection
7. artifact recording

### `loop/candidate`

Builds the candidate-generation input. It must:

- select one failed benchmark case from the most recent run
- extract only that case's failure log as input context
- invoke Codex to modify `ralph-codex` itself

Candidate generation intentionally uses only the most recent failed benchmark
log, not long-term run history.

### `loop/eval`

Runs the benchmark suite and records structured results. It is responsible for:

- executing each benchmark case in isolation
- computing case-level completion metrics
- detecting regressions compared to baseline
- saving machine-readable result files

### `loop/review`

Runs a second Codex call in reviewer mode. Reviewer input is limited to:

- baseline benchmark summary
- candidate benchmark summary
- regression summary
- candidate `git diff`
- failure and improvement summaries

Reviewer output must be JSON with:

- `decision`: `approve` or `reject`
- `reason`
- `risks`
- `suspected_overfit`

Ambiguous reviewer output is treated as rejection.

### `loop/promote`

Promotes only candidates that satisfy all gates. When approved, it:

- creates a promotion branch
- commits the candidate change
- pushes the branch
- opens a PR targeting `main`

### `loop/history`

Stores run artifacts for audit and post-hoc analysis. History is not used as
candidate prompt input in the first version.

## Loop State Machine

Each iteration follows this sequence:

1. `baseline`
   Run the full benchmark suite on the current base revision and save results.
2. `propose`
   Create a candidate branch and run Codex against one failed benchmark log.
3. `candidate-test`
   Re-run the full benchmark suite on the candidate revision.
4. `review`
   Run reviewer Codex on diff plus benchmark summaries.
5. `promote`
   If completion rate improved, regressions are zero, and review approves,
   commit, push, and open a PR.
6. `record`
   Persist artifacts from the full iteration.
7. `repeat`
   Start the next iteration from the latest base state.

## Git and Promotion Strategy

The loop uses separate branches for experiment and promotion.

- `main`: stable branch reviewed by humans
- `loop/<timestamp>-candidate`: temporary experiment branch
- `loop/<timestamp>-promoted`: branch pushed and used for the PR

PRs always target `main`.

The loop handles only one improvement hypothesis per iteration. This keeps
benchmark changes attributable to one candidate cause.

## Benchmark Case Contract

Each benchmark case must define:

- `case_id`
- short description
- fixture repository path
- initialization steps, if any
- `ralph-codex` execution command
- success verification command
- completion counting method

The first implementation should prefer checked-in fixture repositories over
generated repositories.

## Evaluation Output Contract

Each case result must contain at least:

- `case_id`
- `pass`
- `completion_rate`
- `items_total`
- `items_done`
- `failure_summary`
- `artifact_paths`

The full run must also summarize:

- total cases passed
- aggregate completion rate
- regressions relative to baseline
- failed case ids

## Run Artifact Layout

Each loop execution writes to `runs/<timestamp>/` with:

- `baseline.json`
- `candidate.json`
- `review.json`
- `git.diff`
- `logs/`

These artifacts must be sufficient to reproduce the promotion decision later.

## Failure Policy

- If benchmark execution crashes, reject the iteration.
- If the reviewer output is malformed or ambiguous, reject the iteration.
- If benchmark completion rate does not improve, reject the iteration.
- If any previously passing benchmark regresses, reject the iteration.

Rejected runs still write artifacts to disk.

## PR Policy

When promoted, the PR body should include:

- benchmark completion delta versus baseline
- explicit statement that regressions are zero
- a short diff summary
- paths to the relevant benchmark artifacts

## Testing Strategy

The loop implementation should be validated with three layers:

1. unit tests for metadata parsing, score calculation, and promotion gating
2. integration tests for the baseline-to-promotion flow on a small benchmark set
3. local long-running dry runs that confirm artifact reproducibility

## Open Questions Deferred

These are intentionally postponed from the first version:

- CI scheduling
- multiple concurrent candidates
- benchmark sharding
- long-term history-aware prompting
- external benchmark repositories
