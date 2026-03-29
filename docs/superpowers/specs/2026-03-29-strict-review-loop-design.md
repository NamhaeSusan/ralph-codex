# Strict Review Loop Design

## Goal

Add a review-first loop to `ralph-codex` for existing repositories that must go
through repeated full-repository code review, finding-driven fixes, and
mandatory verification.

The first target use case is `trelab-drb-server`.

The v1 implementation should optimize for that repository first, while keeping
the command structure and artifact layout reusable later.

## Non-Goals

- Replacing the existing `ralph-codex run` PRD workflow
- Automatically creating per-iteration commits or branches
- Performing style-only cleanup or broad refactors
- Using diff-only review as the main review mechanism
- Running multiple reviewers or fixers in parallel

## Fixed Product Decisions

These decisions were confirmed for `trelab-drb-server` and are part of v1:

- Review scope: the entire repository on every iteration
- Findings scope:
  - bugs
  - security issues
  - authorization issues
  - data integrity issues
  - concurrency issues
  - missing tests
- Verification gate:
  - always run `make fmt`
  - always run `make fix`
  - always run `make lint`
  - always run `make test`
  - run `make hurl` when the change set affects API-level behavior
- Branch strategy: keep working on the current branch with no automatic
  iteration commits
- Stop condition:
  - hard stop at `--max`
  - early stop when review returns zero findings and verification passes

## Why A Separate Command

The existing `ralph-codex run` command is PRD-driven. It expects
`.codex-ralph/prd.json`, selects one pending item, and asks Codex to complete
that item in a fresh context.

The strict review loop has a different execution model:

1. review the full repository
2. fix every reported finding
3. run mandatory verification
4. repeat from step 1

Trying to overload the current `run` command would mix two incompatible state
models. The review loop should therefore be added as a separate command family.

## Command Surface

v1 adds three commands:

- `ralph-codex review-loop --dir <repo> --max <n>`
- `ralph-codex review-status --dir <repo>`
- `ralph-codex review-reset --dir <repo> [--artifacts]`

The existing commands remain unchanged:

- `init`
- `status`
- `reset`
- `run`

This keeps the PRD workflow stable while allowing a distinct review-first mode.

## High-Level Architecture

Each review-loop iteration has three phases owned by the runner.

### 1. Review

Run a dedicated Codex reviewer against the full repository using `codex exec`
with a strict review prompt and an output JSON schema.

The reviewer must:

- reread the repository each iteration
- ignore style, refactor, and taste-based suggestions
- emit only actionable findings with file and line references
- return machine-readable JSON

`codex exec review` is not the primary mechanism here because it is oriented to
reviewing changes. The desired behavior is a fresh full-repository audit on
every iteration.

### 2. Fix

Run a second Codex invocation that receives:

- the structured finding list from the review step
- the repository instructions in the target repo
- the current repository state

The fixer must:

- fix every reported finding in the current iteration
- avoid unrelated cleanup
- add or update tests when a finding requires test coverage
- leave all work on the current branch
- avoid creating commits

### 3. Verify

The runner executes verification commands directly instead of asking Codex to do
so implicitly. This makes the loop deterministic and auditable.

Base verification:

1. `make fmt`
2. `make fix`
3. `make lint`
4. `make test`

Conditional verification:

- run `make hurl` when the modified files indicate API-level or workflow-level
  impact

## Repository Workdir Layout

The loop reuses `.codex-ralph/` but keeps its files separate from the PRD loop.

New files and directories:

- `.codex-ralph/review-loop.json`
- `.codex-ralph/review-config.json`
- `.codex-ralph/review-prompts/full-repo-review.md`
- `.codex-ralph/review-prompts/fix-findings.md`
- `.codex-ralph/review-schemas/findings.json`
- `.codex-ralph/review-runs/<iteration>/`

The PRD artifacts remain untouched:

- `.codex-ralph/prd.json`
- `.codex-ralph/state.json`
- `.codex-ralph/progress.txt`

This separation avoids collisions between task-completion state and review-loop
state.

## Run Semantics

Each `review-loop` invocation is a fresh run.

v1 should not support resuming a partially completed previous run. If the user
starts `review-loop` again, it should:

- create a new run sequence starting from iteration 1
- treat the current repository state as the new baseline
- leave older `review-runs/` artifacts untouched unless `review-reset
  --artifacts` was used

For predictable Hurl gating and artifact auditing, v1 should require a clean
working tree before starting `review-loop`.

## Initialization And Bootstrap

The review-loop assets should be created by extending the existing `init`
command.

`ralph-codex init` should ensure these review files exist without overwriting
user-edited versions:

- `.codex-ralph/review-loop.json`
- `.codex-ralph/review-config.json`
- `.codex-ralph/review-prompts/full-repo-review.md`
- `.codex-ralph/review-prompts/fix-findings.md`
- `.codex-ralph/review-schemas/findings.json`

Behavior rules:

- `init` creates missing review-loop files alongside the existing PRD files
- `review-loop`, `review-status`, and `review-reset` require initialization
- if `.codex-ralph/` is missing, these commands fail with the same style of
  guidance already used by the current runner
- `review-reset` never regenerates prompt or schema templates; it only resets
  state and optional artifacts

## Review State File

`review-loop.json` should be intentionally small. Detailed artifacts belong in
per-run directories.

Suggested shape:

```json
{
  "iteration": 3,
  "status": "verify",
  "last_stop_reason": "",
  "run_started_from_head": "abc1234",
  "last_started_at": "2026-03-29T10:00:00Z",
  "last_completed_at": "2026-03-29T10:12:00Z",
  "last_run_dir": ".codex-ralph/review-runs/0003",
  "last_review": {
    "total": 4,
    "critical": 1,
    "high": 2,
    "medium": 1
  },
  "last_verify": {
    "fmt": "passed",
    "fix": "passed",
    "lint": "passed",
    "test": "passed",
    "hurl": "skipped"
  },
  "needs_hurl": false,
  "managed_server_pid": 12345
}
```

Field intent:

- `iteration`: current loop number
- `status`: `review`, `fix`, `verify`, `complete`, `failed`, or `stopped`
- `last_stop_reason`: empty during active execution; otherwise values such as
  `max_reached`, `verification_failed`, `fix_blocked`, or `review_invalid`
- `run_started_from_head`: `HEAD` commit hash at the start of the current run
- `last_run_dir`: artifact directory for the most recent iteration
- `last_review`: compact summary for `review-status`
- `last_verify`: last verification result summary
- `needs_hurl`: whether the current change set requires Hurl coverage
- `managed_server_pid`: PID of the background server started by the runner

## Review Output Contract

The reviewer must emit JSON with a stable top-level structure:

```json
{
  "summary": "Full-repo review focused on real defects only.",
  "findings": [
    {
      "id": "F-001",
      "severity": "critical",
      "category": "authorization",
      "file": "internal/domain/review/handler/http/comment.go",
      "line": 27,
      "title": "Reviewer can comment without committee assignment",
      "why": "Any reviewer can act on reviews they do not own.",
      "fix": "Require committee membership check before allowing comments.",
      "tests": [
        "Add handler or service test covering unassigned reviewer denial"
      ]
    }
  ]
}
```

Schema rules:

- `findings` may be empty
- each finding must include:
  - stable `id`
  - `severity`
  - `category`
  - `file`
  - `line`
  - short `title`
  - technical `why`
  - concrete `fix`
- a finding without `file` or `line` is invalid
- unsupported categories are invalid
- malformed JSON fails the iteration immediately

## Fix Result Contract

The fixer should also return machine-readable output so the runner can
distinguish success from explicit blockers.

Suggested shape:

```json
{
  "status": "fixed",
  "resolved_findings": ["F-001", "F-002"],
  "blockers": []
}
```

If the fixer cannot safely resolve all findings, it must return:

```json
{
  "status": "blocked",
  "resolved_findings": [],
  "blockers": [
    "F-003 requires a product decision before code changes."
  ]
}
```

Runner rules:

- `status=fixed` requires every review finding id to appear in
  `resolved_findings`
- `status=blocked` fails the iteration immediately
- missing or malformed fixer output fails the iteration immediately
- the retry fixer after verification failure must obey the same contract
- retry fixer artifacts should be written as separate files, such as
  `fix-retry.json` and `fix-retry.txt`

## Reviewer Prompt Contract

The reviewer prompt must explicitly enforce the user-selected boundaries.

Required reviewer rules:

- review the entire repository every iteration
- treat previous findings as non-authoritative
- report only:
  - bugs
  - security issues
  - authorization issues
  - data integrity issues
  - concurrency issues
  - missing tests
- do not report:
  - style issues
  - naming preferences
  - speculative refactors
  - generic architecture opinions without a concrete defect
- produce findings ordered by severity, then confidence
- include file and line references for every finding

## Fixer Prompt Contract

The fixer prompt should be narrower than the current PRD prompt.

Required fixer rules:

- fix every finding from the current review output
- do not introduce unrelated cleanup
- follow target repository instructions such as `AGENTS.md`, `CLAUDE.md`, and
  local workflows
- add tests when the finding indicates a missing test
- keep edits surgical
- do not create commits
- if a finding cannot be safely fixed, stop and explain the blocker

## Hurl Trigger Rules

The target repository requires `make hurl` only for larger API-affecting
changes, and the command requires a running server plus seed data.

For this design, "change set" means the cumulative working tree delta produced
by the current `review-loop` run, measured from the clean repository state at
the start of iteration 1.

The runner should therefore:

- record the starting `HEAD` commit hash and initial clean-tree marker in
  `review-loop.json`
- recompute changed files from the current working tree before each verify phase
- treat `needs_hurl` as sticky for the rest of the run once any trigger path
  appears in that cumulative delta

v1 should use a conservative trigger on that cumulative file set:

- set `needs_hurl=true` if any modified file is under:
  - `cmd/`
  - `internal/`
  - `pkg/`
  - `tests/hurl/`

This rule intentionally over-runs Hurl rather than missing API regressions.

Future versions may refine the trigger by path allowlists or file tags, but v1
should prioritize safety.

## Server Management For Hurl

Hurl orchestration is repository specific. For v1, the runner should keep the
base verification gate fixed in code and use `review-config.json` only for Hurl
and server-management behavior.

`review-config.json` should define:

- Hurl command
- Hurl trigger paths
- optional server start command
- optional healthcheck URL or healthcheck command
- optional seed command
- optional db reset command
- paths that imply schema-sensitive resets

Generic default behavior:

- if no Hurl config is present, skip Hurl orchestration entirely

For `trelab-drb-server`, the review config would encode:

- Hurl trigger paths:
  - `cmd/`
  - `internal/`
  - `pkg/`
  - `tests/hurl/`
- Hurl command:
  - `make hurl`
- server start:
  - `make devrun`
- healthcheck:
  - `http://localhost:8080/health`
- seed:
  - `make seed`
- db reset:
  - `make dbreset`

When `needs_hurl=true`, the runner should manage the configured development
server itself instead of relying on the user to do it manually.

Rules:

- if schema or seed-sensitive files changed and a db reset command is configured:
  - run the configured db reset command
  - start the configured server command in the background
  - wait for the configured healthcheck URL or healthcheck command
  - run the configured seed command when present
  - run the configured Hurl command
- otherwise:
  - start the configured server command in the background
  - wait for the configured healthcheck URL or healthcheck command
  - run the configured Hurl command

The runner must capture server logs into the iteration artifact directory.
The runner must terminate any managed server process on normal completion,
failure, interrupt, and `review-reset`.

On loop startup, if `managed_server_pid` exists, the runner should verify that
the process still matches the configured server command. If it does, terminate
it before starting a new one. If it does not, clear the stale PID and continue.

Hurl orchestration failures should fail the iteration immediately with explicit
stop reasons:

- `db_reset_failed`
- `server_start_failed`
- `healthcheck_failed`
- `seed_failed`
- `hurl_failed`

## Iteration State Machine

Each iteration follows this sequence:

1. initialize run artifact directory
2. write `status=review`
3. run reviewer Codex
4. save `review.json` and reviewer text output
5. if findings are zero:
   - run verification
   - if verification passes, mark `complete` and stop early
   - if verification fails, mark `failed` with `last_stop_reason=verification_failed_after_zero_findings` and stop
6. write `status=fix`
7. run fixer Codex with the full finding list
8. save fixer output
9. if fixer reports `blocked`, mark `failed` with `last_stop_reason=fix_blocked` and stop
10. write `status=verify`
11. run verification commands
12. if verification fails:
   - run the fixer one more time with:
     - original findings
     - verification failure output
   - require the same fixer JSON contract as the first fix pass
   - rerun verification once
13. if verification still fails, mark the loop failed and stop
14. if verification passes, continue to the next iteration unless `--max` was
    reached
15. if `--max` is reached with a successful last iteration, mark `stopped` with
    `last_stop_reason=max_reached`

## Failure Policy

The loop should fail closed.

Immediate failure conditions:

- reviewer process exits non-zero
- reviewer output is not valid JSON
- reviewer output violates schema
- fixer process exits non-zero
- fixer output is malformed
- fixer reports `blocked`
- verification fails twice in the same iteration
- verification fails after a zero-finding review
- `db reset` fails
- server start fails
- healthcheck never passes
- seed command fails
- Hurl command fails

Non-failure conditions:

- reviewer returns zero findings
- reviewer changes severity distribution between iterations
- fixer touches many files, as long as verification passes

## Status And Reset Behavior

`review-status` should report:

- repo path
- current iteration
- current status
- last stop reason
- last review summary
- last verification summary
- last artifact directory

`review-reset` should:

- reset `review-loop.json`
- optionally clear `review-runs/` when `--artifacts` is passed
- terminate any still-running managed server process recorded in state
- never revert or delete repository code changes

This matches the user-selected branch strategy of keeping all work on the same
branch and leaving code history under human control.

## Artifact Layout

Each iteration writes a numbered directory such as
`.codex-ralph/review-runs/0003/` containing:

- `review.json`
- `review.txt`
- `fix.txt`
- `verify.log`
- `server.log` when server management was needed
- optional helper files such as `commands.txt`

Artifacts must be enough to audit why the iteration continued, failed, or
stopped.

## CLI Compatibility

The review loop must reuse the same Codex execution options already supported by
the existing runner where possible:

- `--dir`
- `--max`
- `--dry-run`
- `--dangerous`
- `--model`

This keeps operator expectations consistent and minimizes new surface area.

`review-loop --dry-run` should print, without executing:

- the resolved review prompt path
- the reviewer `codex exec` command
- the fixer `codex exec` command
- the resolved base verification commands
- whether Hurl is configured for the current repo
- the sticky `needs_hurl` decision rule
- the server orchestration commands that would run if Hurl becomes required
- the artifact directory that would be created for iteration 1

## Testing Strategy

The implementation should be validated in layers.

1. Unit tests for:
   - review state file updates
   - finding schema validation
   - `needs_hurl` path classification
   - command selection and failure gating
2. Integration tests for:
   - one successful zero-finding iteration
   - review -> fix -> verify success flow
   - verify failure followed by one retry
   - malformed review JSON rejection
3. Manual validation on `trelab-drb-server` for:
   - full repository review
   - fix pass on real findings
   - server restart and Hurl orchestration

## Deferred Questions

These are intentionally out of scope for v1:

- configurable finding categories per repository
- per-severity stop thresholds
- automatic commit checkpoints
- reviewer and fixer using different models
- artifact pruning and retention policy
