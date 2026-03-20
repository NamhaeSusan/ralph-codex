# Installing `ralph-codex`

Clone the repository anywhere you like:

```bash
git clone <your-repo-url> ~/ralph-codex
cd ~/ralph-codex
```

Run the installer:

```bash
./install.sh
```

This creates:

- `~/.local/bin/ralph-codex`
- `~/.agents/skills/prd`
- `~/.agents/skills/ralph`

Restart Codex after installation so the new skills are discovered.

## Verify

```bash
which ralph-codex
ls -la ~/.agents/skills/prd
ls -la ~/.agents/skills/ralph
```

## Update

```bash
cd ~/ralph-codex
git pull
./install.sh
```

## Uninstall

```bash
cd ~/ralph-codex
./uninstall.sh
```

Optionally delete the clone after uninstalling.
