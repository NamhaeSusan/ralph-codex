# ralph-codex

Fresh-context Ralph workflow for Codex.

This repository packages three things together:

- a `ralph-codex` runner that loops with `codex exec`
- portable templates for `.codex-ralph/`
- Codex skills for writing a PRD and converting it into Ralph JSON

## Why this exists

The upstream Ralph project targets Amp and Claude Code. This version keeps the same
small-task, fresh-context workflow, but swaps the execution layer for Codex.

Each iteration starts a new `codex exec` run and keeps only:

- repository state
- `.codex-ralph/prd.json`
- `.codex-ralph/state.json`
- `.codex-ralph/progress.txt`

## Quickstart

```bash
git clone <your-repo-url> ~/ralph-codex
cd ~/ralph-codex
./install.sh
```

Restart Codex after installation so native skill discovery picks up `prd` and `ralph`.

Then, inside any Git repository:

```bash
ralph-codex init --dir /path/to/repo
ralph-codex status --dir /path/to/repo
ralph-codex run --dir /path/to/repo --max 5
```

## Workflow

1. Run `ralph-codex init --dir /path/to/repo`.
2. In Codex, ask for a PRD using the `prd` skill.
3. In Codex, ask the `ralph` skill to convert that PRD into `.codex-ralph/prd.json`.
4. Run `ralph-codex status --dir /path/to/repo`.
5. Run `ralph-codex run --dir /path/to/repo --max 5`.

## Install Locations

`install.sh` creates these symlinks:

- `~/.local/bin/ralph-codex`
- `~/.agents/skills/prd`
- `~/.agents/skills/ralph`

The repo itself can live anywhere. The command resolves templates and skills relative
to its own repository root.

## Commands

```bash
ralph-codex init --dir /path/to/repo
ralph-codex status --dir /path/to/repo
ralph-codex run --dir /path/to/repo --max 5
ralph-codex run --dir /path/to/repo --max 1 --dry-run
ralph-codex run --dir /path/to/repo --max 5 --dangerous
ralph-codex run --dir /path/to/repo --max 5 --model o3
```

## Repository Layout

- `bin/ralph-codex`: portable runner
- `templates/`: files copied into `.codex-ralph/`
- `skills/`: Codex-discoverable skills
- `install.sh`: local installer
- `uninstall.sh`: local uninstaller

## Notes

- The runner uses the real `codex` binary, not shell aliases.
- Default execution mode is `--full-auto`.
- Use `--dangerous` only when a repository truly needs unrestricted execution.
- `prd.json` supports the Ralph `userStories[].passes` schema and the older
  `tasks[].status` schema, but `userStories` is the recommended format.
- This repo vendors and adapts parts of `snarktank/ralph`. See `THIRD_PARTY_NOTICES.md`.
