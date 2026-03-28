# Code Review and Usability Improvements

## Changes

### bin/ralph-codex
- Replaced `pending_items()` with `split_items()` that returns both done and pending lists
- Eliminated redundant double call to `load_items()` in `cmd_status`
- Updated `cmd_run` to use `split_items()` consistently
- Added help text to all argparse arguments and subcommands
- Changed `--dir` from required to optional (defaults to current directory)
- Added progress display in `cmd_run`: `[2/6 done]`
- Added iteration count and last run time to `cmd_status`
- Added `.gitignore` hint in `cmd_init` when `.codex-ralph/` not ignored
- cmd_run: end-of-run summary with items completed and elapsed time
- cmd_run: per-iteration elapsed time display
- cmd_status: list all pending items when more than one
- ensure_initialized: cleaner error message
- cmd_run: consolidated duplicate COMPLETE check blocks (3 → 1)
- cmd_run: accurate completed count even on codex failure

### install.sh
- Added PATH check: warns user if `~/.local/bin` is not in PATH

### uninstall.sh
- Added completion message after removing symlinks

### README.md
- Added `--model` flag example to Commands section
- Updated all examples to use simpler `--dir`-less syntax
- Documented that `--dir` defaults to current directory
