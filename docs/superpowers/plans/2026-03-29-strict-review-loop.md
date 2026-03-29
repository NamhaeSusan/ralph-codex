# Strict Review Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `review-loop` command family to `ralph-codex` that performs full-repository review, finding-driven fixes, and mandatory verification for `trelab-drb-server`.

**Architecture:** Extend the existing single-file runner in `bin/ralph-codex` with a second workflow alongside the PRD loop. Keep the base verification gate hardcoded for v1, generate review-loop templates under `.codex-ralph/`, and store per-iteration artifacts in a dedicated review run directory.

**Tech Stack:** Python 3.10 CLI runner, `codex exec`, JSON templates/schemas, `unittest`, `unittest.mock`, Git working tree state

---

### Task 1: Add Review-Loop Templates And Bootstrap

**Files:**
- Modify: `bin/ralph-codex`
- Create: `templates/review-loop.json`
- Create: `templates/review-config.json`
- Create: `templates/review-prompts/full-repo-review.md`
- Create: `templates/review-prompts/fix-findings.md`
- Create: `templates/review-schemas/findings.json`
- Create: `templates/review-schemas/fix-result.json`
- Test: `tests/test_review_loop_init.py`

- [ ] **Step 1: Write the failing bootstrap test**

```python
def test_init_creates_review_loop_files(self):
    repo = self.make_git_repo()
    result = self.run_cli(repo, "init")
    self.assertEqual(result.returncode, 0)
    self.assertTrue((repo / ".codex-ralph" / "review-loop.json").exists())
    self.assertTrue((repo / ".codex-ralph" / "review-config.json").exists())
    self.assertTrue((repo / ".codex-ralph" / "review-prompts" / "full-repo-review.md").exists())
    self.assertTrue((repo / ".codex-ralph" / "review-schemas" / "findings.json").exists())

def test_init_keeps_existing_review_prompt(self):
    repo = self.make_git_repo()
    prompt = repo / ".codex-ralph" / "review-prompts" / "full-repo-review.md"
    prompt.parent.mkdir(parents=True, exist_ok=True)
    prompt.write_text("custom prompt")
    result = self.run_cli(repo, "init")
    self.assertEqual(result.returncode, 0)
    self.assertEqual(prompt.read_text(), "custom prompt")
```

- [ ] **Step 2: Run the bootstrap test to confirm failure**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_init.py' -v`
Expected: FAIL because `init` does not yet create review-loop files.

- [ ] **Step 3: Add template files and init wiring**

```python
REVIEW_TEMPLATE_PATHS = (
    "review-loop.json",
    "review-config.json",
    "review-prompts/full-repo-review.md",
    "review-prompts/fix-findings.md",
    "review-schemas/findings.json",
    "review-schemas/fix-result.json",
)
```

```python
def ensure_template_file(name: str, destination_root: Path) -> Path:
    source = template_path(name)
    destination = destination_root / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        shutil.copy2(source, destination)
    return destination
```

```text
full-repo-review.md must explicitly say:
- review the full repository every iteration
- treat previous findings as non-authoritative
- only report bug/security/authorization/data_integrity/concurrency/missing_test
- exclude style/refactor/taste findings
- require file and line for every finding
- order findings by severity, then confidence
```

- [ ] **Step 4: Re-run the bootstrap test**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_init.py' -v`
Expected: PASS

- [ ] **Step 5: Commit the bootstrap changes**

```bash
git add bin/ralph-codex templates/review-loop.json templates/review-config.json templates/review-prompts/full-repo-review.md templates/review-prompts/fix-findings.md templates/review-schemas/findings.json templates/review-schemas/fix-result.json tests/test_review_loop_init.py
git commit -m "feat: bootstrap review loop templates" -m "History: claude_history/2026-03-29-review-loop-design.md"
```

### Task 2: Add Review-Loop State And CLI Surface

**Files:**
- Modify: `bin/ralph-codex`
- Test: `tests/test_review_loop_state.py`

- [ ] **Step 1: Write failing CLI/state tests**

```python
def test_review_status_requires_initialized_review_loop(self):
    repo = self.make_git_repo()
    result = self.run_cli(repo, "review-status")
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("Run `ralph-codex init`", result.stderr)

def test_review_reset_supports_artifacts_flag(self):
    repo = self.make_initialized_repo()
    result = self.run_cli(repo, "review-reset", "--artifacts")
    self.assertEqual(result.returncode, 0)

def test_review_loop_rejects_dirty_worktree(self):
    repo = self.make_initialized_repo()
    (repo / "dirty.txt").write_text("dirty")
    result = self.run_cli(repo, "review-loop", "--max", "1")
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("clean working tree", result.stderr)

def test_review_loop_starts_new_run_at_iteration_one(self):
    repo = self.make_initialized_repo()
    first = prepare_new_review_run(repo)
    second = prepare_new_review_run(repo)
    self.assertEqual(first["iteration"], 1)
    self.assertEqual(second["iteration"], 1)
    self.assertNotEqual(first["run_dir"], second["run_dir"])

def test_review_loop_dry_run_prints_commands(self):
    repo = self.make_initialized_repo()
    result = self.run_cli(repo, "review-loop", "--max", "1", "--dry-run")
    self.assertEqual(result.returncode, 0)
    self.assertIn("reviewer", result.stdout)
    self.assertIn("fixer", result.stdout)
    self.assertIn("make fmt", result.stdout)
    self.assertIn("artifact directory", result.stdout)
```

- [ ] **Step 2: Run the state tests to confirm failure**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_state.py' -v`
Expected: FAIL because the commands and flags do not exist yet.

- [ ] **Step 3: Implement review-loop paths, state helpers, and parser entries**

```python
def review_state_path(target: Path) -> Path:
    return target / "review-loop.json"

def review_runs_dir(target: Path) -> Path:
    return target / "review-runs"
```

```python
review_loop_parser = subparsers.add_parser("review-loop", help="run strict review loop")
review_status_parser = subparsers.add_parser("review-status", help="show review loop state")
review_reset_parser = subparsers.add_parser("review-reset", help="reset review loop state")
review_reset_parser.add_argument("--artifacts", action="store_true")
```

```python
def require_clean_worktree(repo: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(repo), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.stdout.strip():
        raise SystemExit(fail("review-loop requires a clean working tree"))
```

```python
def prepare_new_review_run(repo: Path, target: Path) -> dict:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = review_runs_dir(target) / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    return {"iteration": 1, "run_dir": str(run_dir)}
```

- [ ] **Step 4: Re-run the state tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_state.py' -v`
Expected: PASS

- [ ] **Step 5: Commit the CLI/state changes**

```bash
git add bin/ralph-codex tests/test_review_loop_state.py
git commit -m "feat: add review loop command surface" -m "History: claude_history/2026-03-29-review-loop-design.md"
```

### Task 3: Add Reviewer And Fixer Execution Contracts

**Files:**
- Modify: `bin/ralph-codex`
- Modify: `templates/review-prompts/full-repo-review.md`
- Modify: `templates/review-prompts/fix-findings.md`
- Modify: `templates/review-schemas/findings.json`
- Modify: `templates/review-schemas/fix-result.json`
- Test: `tests/test_review_loop_exec.py`

- [ ] **Step 1: Write failing execution-contract tests**

```python
def test_review_loop_rejects_invalid_review_json(self):
    result = run_review_phase_with_output("not json")
    self.assertEqual(result.stop_reason, "review_invalid")

def test_review_loop_rejects_missing_file_or_line(self):
    result = run_review_phase_with_output({
        "summary": "bad",
        "findings": [{"id": "F-1", "severity": "high", "category": "bug"}],
    })
    self.assertEqual(result.stop_reason, "review_invalid")

def test_review_loop_rejects_unsupported_category(self):
    result = run_review_phase_with_output({
        "summary": "bad",
        "findings": [{
            "id": "F-1",
            "severity": "high",
            "category": "style",
            "file": "bin/ralph-codex",
            "line": 1,
            "title": "style only",
            "why": "bad",
            "fix": "bad",
        }],
    })
    self.assertEqual(result.stop_reason, "review_invalid")

def test_fix_phase_rejects_blocked_result(self):
    result = run_fix_phase_with_output({
        "status": "blocked",
        "resolved_findings": [],
        "blockers": ["F-001 requires human input"],
    })
    self.assertEqual(result.stop_reason, "fix_blocked")
```

- [ ] **Step 2: Run the execution-contract tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_exec.py' -v`
Expected: FAIL because review/fix schema validation does not exist yet.

- [ ] **Step 3: Implement reviewer/fixer command builders and JSON validation**

```python
def review_command(repo: Path, output_file: Path, schema_file: Path, dangerous: bool, model: str | None) -> list[str]:
    cmd = codex_command(repo, output_file, dangerous, model)
    cmd.extend(["--output-schema", str(schema_file)])
    return cmd
```

```python
def validate_fix_result(payload: dict, finding_ids: set[str]) -> None:
    if payload.get("status") == "fixed":
        if set(payload.get("resolved_findings", [])) != finding_ids:
            raise ValueError("resolved findings mismatch")
        return
    if payload.get("status") == "blocked":
        return
    raise ValueError("invalid fix result status")
```

```text
fix-findings.md must explicitly say:
- obey target repo instructions
- do not create commits
- fix only listed findings
- add or update tests for missing-test findings
- stop with blocked output when a safe fix is not possible
```

- [ ] **Step 4: Re-run the execution-contract tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_exec.py' -v`
Expected: PASS

- [ ] **Step 5: Commit the review/fix execution changes**

```bash
git add bin/ralph-codex tests/test_review_loop_exec.py
git commit -m "feat: validate review loop codex contracts" -m "History: claude_history/2026-03-29-review-loop-design.md"
```

### Task 4: Add Verify And Hurl Orchestration

**Files:**
- Modify: `bin/ralph-codex`
- Test: `tests/test_review_loop_verify.py`

- [ ] **Step 1: Write failing verify/Hurl tests**

```python
def test_verify_runs_base_commands_in_order(self):
    calls = []
    run_verify(fake_runner(calls), needs_hurl=False)
    self.assertEqual(calls[:4], [
        ["make", "fmt"],
        ["make", "fix"],
        ["make", "lint"],
        ["make", "test"],
    ])

def test_hurl_trigger_becomes_sticky_after_backend_change(self):
    changed = {"internal/domain/review/service.go"}
    self.assertTrue(compute_needs_hurl(changed, already_needed=False))
    self.assertTrue(compute_needs_hurl(set(), already_needed=True))

def test_review_loop_records_run_head_and_baseline(self):
    state = start_review_run(repo=self.repo)
    self.assertIn("run_started_from_head", state)
    self.assertTrue(state["run_started_from_head"])
    self.assertIn("clean_tree_marker", state)

def test_review_loop_cleans_stale_managed_server_pid(self):
    state = {"managed_server_pid": 99999}
    cleanup_stale_server(state, config={"server_start": ["make", "devrun"]})
    self.assertEqual(state["managed_server_pid"], 0)

def test_review_loop_skips_hurl_when_config_has_no_hurl_section(self):
    verify = run_verify_with_config(config={}, changed_files={"internal/x.go"})
    self.assertEqual(verify["hurl"], "skipped")

def test_review_loop_loads_review_config_contract(self):
    config = load_review_config(self.repo)
    self.assertIn("hurl_command", config)
    self.assertIn("trigger_paths", config)
    self.assertIn("healthcheck", config)
```

- [ ] **Step 2: Run the verify/Hurl tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_verify.py' -v`
Expected: FAIL because verify orchestration does not exist yet.

- [ ] **Step 3: Implement base verify, Hurl trigger, and stop reasons**

```python
BASE_VERIFY_COMMANDS = (
    ["make", "fmt"],
    ["make", "fix"],
    ["make", "lint"],
    ["make", "test"],
)
```

```python
HURL_STOP_REASONS = {
    "db_reset": "db_reset_failed",
    "server_start": "server_start_failed",
    "healthcheck": "healthcheck_failed",
    "seed": "seed_failed",
    "hurl": "hurl_failed",
}
```

```python
def compute_changed_files_since_run_start(repo: Path, start_head: str) -> set[str]:
    result = subprocess.run(
        ["git", "-C", str(repo), "diff", "--name-only", start_head],
        capture_output=True,
        text=True,
        check=False,
    )
    untracked = subprocess.run(
        ["git", "-C", str(repo), "ls-files", "--others", "--exclude-standard"],
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        line
        for line in (result.stdout.splitlines() + untracked.stdout.splitlines())
        if line
    }
```

```python
def cleanup_managed_server(state: dict) -> None:
    if not state.get("managed_server_pid"):
        return
    os.kill(state["managed_server_pid"], signal.SIGTERM)
    state["managed_server_pid"] = 0
```

```python
server_log = run_dir / "server.log"
server_proc = start_managed_server(config, log_path=server_log)
try:
    wait_for_healthcheck(config)
finally:
    cleanup_managed_server(state)
```

- [ ] **Step 4: Re-run the verify/Hurl tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_verify.py' -v`
Expected: PASS

- [ ] **Step 5: Commit the verify/Hurl changes**

```bash
git add bin/ralph-codex tests/test_review_loop_verify.py
git commit -m "feat: add review loop verification flow" -m "History: claude_history/2026-03-29-review-loop-design.md"
```

### Task 5: Add Full Review-Loop Iteration Flow

**Files:**
- Modify: `bin/ralph-codex`
- Test: `tests/test_review_loop_run.py`

- [ ] **Step 1: Write failing end-to-end loop tests**

```python
def test_review_loop_stops_early_on_zero_findings(self):
    result = self.run_review_loop_with_fake_codex(
        review_payload={"summary": "clean", "findings": []},
        verify_exit_codes=[0, 0, 0, 0],
    )
    self.assertEqual(result.returncode, 0)
    self.assertEqual(result.state["status"], "complete")

def test_review_loop_runs_review_fix_verify_successfully(self):
    result = self.run_review_loop_with_fake_codex(
        review_payload={"summary": "found", "findings": [self.sample_finding()]},
        fix_payloads=[self.fixed_payload()],
        verify_exit_codes=[0, 0, 0, 0],
    )
    self.assertEqual(result.returncode, 0)
    self.assertTrue((result.run_dir / "review.json").exists())
    self.assertTrue((result.run_dir / "fix.txt").exists())
    self.assertTrue((result.run_dir / "verify.log").exists())

def test_review_loop_stops_with_max_reached_after_successful_last_iteration(self):
    result = self.run_review_loop_with_fake_codex(
        review_payloads=[
            {"summary": "found", "findings": [self.sample_finding()]},
            {"summary": "found", "findings": [self.sample_finding()]},
        ],
        fix_payloads=[self.fixed_payload(), self.fixed_payload()],
        verify_exit_codes=[0, 0, 0, 0, 0, 0, 0, 0],
        max_iterations=2,
    )
    self.assertEqual(result.state["status"], "stopped")
    self.assertEqual(result.state["last_stop_reason"], "max_reached")

def test_review_loop_retries_fix_once_after_verify_failure(self):
    result = self.run_review_loop_with_fake_codex(
        review_payload={"summary": "found", "findings": [self.sample_finding()]},
        fix_payloads=[self.fixed_payload(), self.fixed_payload()],
        verify_exit_codes=[0, 0, 0, 1, 0, 0, 0, 0],
    )
    self.assertEqual(result.state["last_stop_reason"], "")
    self.assertTrue((result.run_dir / "fix-retry.json").exists())
    self.assertTrue((result.run_dir / "fix-retry.txt").exists())

def test_review_loop_fails_closed_after_second_verify_failure(self):
    result = self.run_review_loop_with_fake_codex(
        review_payload={"summary": "found", "findings": [self.sample_finding()]},
        fix_payloads=[self.fixed_payload(), self.fixed_payload()],
        verify_exit_codes=[0, 0, 0, 1, 0, 0, 0, 1],
    )
    self.assertEqual(result.returncode, 1)
    self.assertEqual(result.state["status"], "failed")

def test_review_loop_fails_when_zero_findings_verify_fails(self):
    result = self.run_review_loop_with_fake_codex(
        review_payload={"summary": "clean", "findings": []},
        verify_exit_codes=[0, 0, 0, 1],
    )
    self.assertEqual(result.returncode, 1)
    self.assertEqual(
        result.state["last_stop_reason"],
        "verification_failed_after_zero_findings",
    )
```

- [ ] **Step 2: Run the end-to-end loop tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_run.py' -v`
Expected: FAIL because `cmd_review_loop` does not yet orchestrate the full flow.

- [ ] **Step 3: Implement the iteration state machine**

```python
for iteration in range(1, args.max + 1):
    state["iteration"] = iteration
    state["status"] = "review"
    review_payload = run_review_phase(...)
    if not review_payload["findings"]:
        verify_result = run_verify_phase(...)
        if verify_result.ok:
            state["status"] = "complete"
            return 0
        state["status"] = "failed"
        state["last_stop_reason"] = "verification_failed_after_zero_findings"
        return 1
```

```python
write_json(run_dir / "review.json", review_payload)
(run_dir / "review.txt").write_text(review_text)
(run_dir / "fix.txt").write_text(fix_text)
(run_dir / "verify.log").write_text(verify_output)
```

```python
retry_payload = run_fix_phase(
    findings=review_payload["findings"],
    verification_failure_output=verify_output,
)
write_json(run_dir / "fix-retry.json", retry_payload)
(run_dir / "fix-retry.txt").write_text(retry_text)
```

- [ ] **Step 4: Re-run the end-to-end loop tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_run.py' -v`
Expected: PASS

- [ ] **Step 5: Commit the loop orchestration changes**

```bash
git add bin/ralph-codex tests/test_review_loop_run.py
git commit -m "feat: add strict review loop runner" -m "History: claude_history/2026-03-29-review-loop-design.md"
```

### Task 6: Update Status, Reset, And Artifact Reporting

**Files:**
- Modify: `bin/ralph-codex`
- Test: `tests/test_review_loop_status_reset.py`

- [ ] **Step 1: Write failing status/reset tests**

```python
def test_review_status_prints_stop_reason(self):
    output = render_review_status({
        "iteration": 2,
        "status": "stopped",
        "last_stop_reason": "max_reached",
    })
    self.assertIn("max_reached", output)

def test_review_status_prints_repo_and_summaries(self):
    output = render_review_status({
        "iteration": 2,
        "status": "failed",
        "last_review": {"total": 3, "critical": 1, "high": 1, "medium": 1},
        "last_verify": {"fmt": "passed", "fix": "passed", "lint": "failed", "test": "skipped", "hurl": "skipped"},
        "last_run_dir": ".codex-ralph/review-runs/0002",
    }, repo="/tmp/repo")
    self.assertIn("/tmp/repo", output)
    self.assertIn("critical", output)
    self.assertIn("review-runs/0002", output)

def test_review_reset_removes_artifacts_only_with_flag(self):
    result = self.run_cli(self.repo, "review-reset")
    self.assertTrue((self.review_runs_dir / "0001").exists())

def test_review_reset_terminates_managed_server(self):
    result = self.run_review_reset_with_pid(12345, artifacts=False)
    self.assertEqual(result.returncode, 0)
    self.assertTrue(result.kill_called)

def test_review_status_prints_last_verification_summary(self):
    output = render_review_status({
        "last_verify": {"fmt": "passed", "fix": "passed", "lint": "passed", "test": "passed", "hurl": "passed"},
        "last_run_dir": ".codex-ralph/review-runs/run-1/0001",
    }, repo="/tmp/repo")
    self.assertIn("hurl", output)

def test_review_loop_dry_run_reports_hurl_rules(self):
    output = render_review_dry_run(config=self.sample_config())
    self.assertIn("sticky", output)
    self.assertIn("Hurl configured", output)
    self.assertIn("iteration 1", output)
```

- [ ] **Step 2: Run the status/reset tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_status_reset.py' -v`
Expected: FAIL because reporting and `--artifacts` handling are incomplete.

- [ ] **Step 3: Implement output formatting and artifact cleanup**

```python
if args.artifacts and review_runs_dir(target).exists():
    shutil.rmtree(review_runs_dir(target))
```

```python
print(f"status:    {state['status']}")
print(f"stop:      {state.get('last_stop_reason', '')}")
print(f"last run:  {state.get('last_run_dir', '')}")
```

```python
print(f"repo:      {repo}")
print(f"review:    {state.get('last_review', {})}")
print(f"verify:    {state.get('last_verify', {})}")
```

- [ ] **Step 4: Re-run the status/reset tests**

Run: `python3 -m unittest discover -s tests -p 'test_review_loop_status_reset.py' -v`
Expected: PASS

- [ ] **Step 5: Commit the status/reset changes**

```bash
git add bin/ralph-codex tests/test_review_loop_status_reset.py
git commit -m "feat: add review loop status and reset" -m "History: claude_history/2026-03-29-review-loop-design.md"
```

### Task 7: Update User Documentation And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `claude_history/2026-03-29-review-loop-design.md`

- [ ] **Step 1: Write the doc delta before editing**

```markdown
- Add `review-loop`, `review-status`, and `review-reset --artifacts`
- Explain that v1 targets `trelab-drb-server`
- Document generated review-loop files under `.codex-ralph/`
```

- [ ] **Step 2: Update README and any checklist references**

Run: `sed -n '1,220p' README.md`
Expected: existing command section is ready to extend with review-loop examples.

- [ ] **Step 3: Run project verification**

Run: `ruff check bin/ralph-codex`
Expected: PASS

Run: `ruff format bin/ralph-codex`
Expected: formats without error

Run: `python3 -m unittest discover -s tests -v`
Expected: PASS

- [ ] **Step 4: Run manual validation against `trelab-drb-server`**

Run: `ralph-codex init --dir /Users/kimtaeyun/trelab-workspace/trelab-drb/trelab-drb-server`
Expected: review-loop files appear under `.codex-ralph/`

Run: `ralph-codex review-loop --dir /Users/kimtaeyun/trelab-workspace/trelab-drb/trelab-drb-server --max 1 --dry-run`
Expected: reviewer/fixer commands, base verify commands, and Hurl orchestration plan are printed

Run: `ralph-codex review-loop --dir /Users/kimtaeyun/trelab-workspace/trelab-drb/trelab-drb-server --max 1`
Expected: one real full-repository review iteration runs, writes review artifacts, and either exits cleanly after verification or fails with an explicit stop reason

- [ ] **Step 5: Record final work log**

```markdown
## Verification
- `ruff check bin/ralph-codex`
- `ruff format bin/ralph-codex`
- `python3 -m unittest discover -s tests -v`
- `ralph-codex init --dir /Users/kimtaeyun/trelab-workspace/trelab-drb/trelab-drb-server`
- `ralph-codex review-loop --dir /Users/kimtaeyun/trelab-workspace/trelab-drb/trelab-drb-server --max 1 --dry-run`
```

- [ ] **Step 6: Commit the docs and verification pass**

```bash
git add README.md claude_history/2026-03-29-review-loop-design.md
git commit -m "docs: document strict review loop commands" -m "History: claude_history/2026-03-29-review-loop-design.md"
```
