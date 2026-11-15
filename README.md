# tmux-phoenix

Zero-loss `tmux` session persistence, crash recovery, and snapshot management for Linux workstations and servers.

`tmux-phoenix` orchestrates [TPM](https://github.com/tmux-plugins/tpm), [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect), [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum), and a `systemd` user daemon into a single, self-healing CLI tool (`tmux-phoenix` and short alias `tpx`). Your sessions, pane layouts, working directories, and running foreground processes survive system reboots and server crashes automatically.

## Features

- **Automatic Boot and Crash Recovery:** Configures a `systemd` user unit with `loginctl` lingering so your `tmux` server starts at boot and restores all sessions before you log in via SSH.
- **Self-Healing Snapshots:** Automatically deletes 0-byte snapshot files caused by abrupt power loss, strips temporary bootstrap session records (`__autostart`), and repairs the `last` symlink to the newest valid snapshot before restoration.
- **Bounded Disk Usage:** Disables scrollback archive compression (`pane_contents.tar.gz`) by default and automatically prunes older layout snapshots to retain the newest 20 non-empty files while protecting whichever snapshot `last` targets.
- **Safe Command and Directory Editing:** Provides `list`, `set`, and `edit` commands with strict 11-column TSV validation so tab delimiters are never corrupted.
- **Zero Runtime Dependencies:** Implemented purely in Bash and GNU coreutils (`awk`, `sed`, `find`, `git`), avoiding Python or Conda path issues during early `systemd` boot.

## Prerequisites

- Linux with `systemd` user services and `loginctl`
- `tmux` (version 3.0 or newer)
- `git`, `awk`, `sed`, `find`

## Installation

```bash
git clone https://github.com/hmartiniano/tmux-phoenix.git
cd tmux-phoenix
make install
```

`make install` runs `install.sh`, which symlinks `tmux-phoenix` and `tpx` into `~/.local/bin` and runs `tmux-phoenix setup` (you can also run `./install.sh` directly if `make` is not installed). To install to a custom prefix:

```bash
make install PREFIX=/usr/local
```

## Configuration

Create `~/.config/tmux-phoenix/config` to override defaults per host:

```bash
# Number of non-empty layout snapshots to retain (default: 20)
KEEP_SNAPSHOTS=20

# Continuum autosave interval in minutes (default: 1)
SAVE_INTERVAL=1

# Processes to restore: ':all:' or a space-separated list (e.g., 'ssh htop "~python"')
RESURRECT_PROCESSES=':all:'

# Capture pane scrollback buffers into pane_contents.tar.gz ('on' or 'off', default: 'off')
CAPTURE_PANE_CONTENTS='off'
```

Re-run `tmux-phoenix setup` after changing configuration values.

## Usage

### Lifecycle and Diagnostics

```bash
# Install or update plugins, tmux.conf hooks, and the systemd user service
# (preserves active tmux sessions; pass --restart to force-restart tmux.service)
tmux-phoenix setup

# Show systemd service health, plugin path, active sessions, and snapshot table
tmux-phoenix status

# Run diagnostic checks (lingering, socket environment, options, unit state)
tmux-phoenix doctor

# Trigger an immediate snapshot and prune older files
tmux-phoenix save

# Restore sessions immediately from the 'last' snapshot
tmux-phoenix restore

# Manually prune snapshots to a custom retention count
tmux-phoenix prune 15
```

### Inspecting and Editing Restored Commands

```bash
# Display all saved sessions, directories, and commands
tmux-phoenix list

# Update the startup command for a specific pane (SESSION:WINDOW.PANE)
tmux-phoenix set work:0.0 "python3 train.py --resume"

# Update both command and working directory
tmux-phoenix set work:0.0 "snakemake --cores 8" "/tank/pipelines/run1"

# Revert a pane to an idle shell
tmux-phoenix set work:0.0 ""

# Edit all pane directories and commands in $EDITOR using a 3-column TSV view
tmux-phoenix edit
```

### Rolling Back to an Older Snapshot

```bash
cd ~/.local/share/tmux/resurrect
ls -lt
ln -sf tmux_resurrect_<TIMESTAMP>.txt last
tmux-phoenix restore
```

## Uninstallation

```bash
make uninstall
```

This disables `tmux.service`, removes the managed block from `tmux.conf`, and removes the symlinks in `~/.local/bin` while preserving your saved snapshot files.
