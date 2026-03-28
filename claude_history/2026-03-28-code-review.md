# Code Review and Improvements

## Changes

### bin/ralph-codex
- Replaced `pending_items()` with `split_items()` that returns both done and pending lists
- Eliminated redundant double call to `load_items()` in `cmd_status`
- Updated `cmd_run` to use `split_items()` consistently

### install.sh
- Added PATH check: warns user if `~/.local/bin` is not in PATH

### uninstall.sh
- Added completion message after removing symlinks
