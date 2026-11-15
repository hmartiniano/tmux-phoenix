#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PHOENIX="${REPO_DIR}/bin/tmux-phoenix"

TMP_HOME=$(mktemp -d /tmp/tmux_phoenix_test.XXXXXX)
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME"
export XDG_CONFIG_HOME="${TMP_HOME}/.config"
RESURRECT_DIR="${HOME}/.local/share/tmux/resurrect"
mkdir -p "$RESURRECT_DIR"

echo "Running isolated snapshot tests in ${TMP_HOME}..."

# 1. Seed 25 snapshots, including a 0-byte file and leftover __autostart records
for i in $(seq -w 1 25); do
    snap="${RESURRECT_DIR}/tmux_resurrect_20261113T1000${i}.txt"
    printf 'pane\twork\t0\t1\t:*\t0\tbash\t:/tmp\t1\tpython\t:python3 job_%s.py\n' "$i" > "$snap"
    printf 'pane\t__autostart\t0\t1\t:*\t0\tzsh\t:/tmp\t1\tzsh\t:\n' >> "$snap"
    printf 'window\twork\t0\t:python\t1\t:*\t0000,80x24,0,0,0\t:\n' >> "$snap"
    printf 'window\t__autostart\t0\t:zsh\t1\t:*\t0000,80x24,0,0,1\t:\n' >> "$snap"
    printf 'state\twork\t\n' >> "$snap"
    touch -d "2026-11-13 10:00:${i}" "$snap"
done

# Create a 0-byte snapshot and point 'last' to it
EMPTY_SNAP="${RESURRECT_DIR}/tmux_resurrect_20261113T100099.txt"
: > "$EMPTY_SNAP"
ln -sf "$(basename "$EMPTY_SNAP")" "${RESURRECT_DIR}/last"

# 2. Run prune and verify 0-byte deletion, symlink repair, __autostart removal, and 20-file cap
"$PHOENIX" prune 20

[ ! -e "$EMPTY_SNAP" ] || { echo "FAIL: 0-byte snapshot was not deleted"; exit 1; }

COUNT=$(find "$RESURRECT_DIR" -maxdepth 1 -name 'tmux_resurrect_*.txt' | wc -l)
[ "$COUNT" -eq 20 ] || { echo "FAIL: Expected 20 retained snapshots, found $COUNT"; exit 1; }

ACTIVE=$(readlink -f "${RESURRECT_DIR}/last")
[ "$(basename "$ACTIVE")" = "tmux_resurrect_20261113T100025.txt" ] || {
    echo "FAIL: Expected 'last' to repair to 25, got $(basename "$ACTIVE")"
    exit 1
}

if grep -q "__autostart" "$ACTIVE"; then
    echo "FAIL: __autostart record was not stripped from snapshot"
    exit 1
fi

# 3. Verify 'set' subcommand updates command and directory while preserving 11-column TSV structure
"$PHOENIX" set work:0.0 "snakemake --cores 4" "/tank/data"
"$PHOENIX" list | grep -q "/tank/data" || { echo "FAIL: Directory update not reflected in list"; exit 1; }
"$PHOENIX" list | grep -q "snakemake --cores 4" || { echo "FAIL: Command update not reflected in list"; exit 1; }

# 4. Verify paneless (__autostart-only) snapshots are deleted and 'last' repairs to newest valid snapshot
VALID_BEFORE=$(readlink -f "${RESURRECT_DIR}/last")
PANELESS_SNAP="${RESURRECT_DIR}/tmux_resurrect_20261113T235959.txt"
printf 'pane\t__autostart\t0\t1\t:*\t0\tzsh\t:/tmp\t1\tzsh\t:\n' > "$PANELESS_SNAP"
printf 'window\t__autostart\t0\t:zsh\t1\t:*\t0000,80x24,0,0,1\t:\n' >> "$PANELESS_SNAP"
printf 'state\t__autostart\t\n' >> "$PANELESS_SNAP"
ln -sf "$(basename "$PANELESS_SNAP")" "${RESURRECT_DIR}/last"

"$PHOENIX" prune 20
[ ! -e "$PANELESS_SNAP" ] || { echo "FAIL: Paneless __autostart-only snapshot was not deleted"; exit 1; }
[ "$(readlink -f "${RESURRECT_DIR}/last")" = "$VALID_BEFORE" ] || {
    echo "FAIL: Expected 'last' to repair back to $(basename "$VALID_BEFORE") after paneless prune"
    exit 1
}

# 5. Verify 'edit' subcommand applies valid TSV edits and rejects malformed space-separated edits
VALID_EDITOR="${TMP_HOME}/valid_editor.sh"
cat << 'EOF' > "$VALID_EDITOR"
#!/usr/bin/env bash
printf '# comment\nwork:0.0\t/srv/pipeline\tpython3 run_pipeline.py --fast\n' > "$1"
EOF
chmod +x "$VALID_EDITOR"
EDITOR="$VALID_EDITOR" "$PHOENIX" edit
"$PHOENIX" list | grep -q "/srv/pipeline" || { echo "FAIL: 'edit' directory update not reflected in list"; exit 1; }
"$PHOENIX" list | grep -q "python3 run_pipeline.py --fast" || { echo "FAIL: 'edit' command update not reflected in list"; exit 1; }

SNAP_BEFORE_BAD_EDIT=$(readlink -f "${RESURRECT_DIR}/last")
BAD_EDITOR="${TMP_HOME}/bad_editor.sh"
cat << 'EOF' > "$BAD_EDITOR"
#!/usr/bin/env bash
printf 'work:0.0 /srv/broken_spaces_instead_of_tabs python3 bad.py\n' > "$1"
EOF
chmod +x "$BAD_EDITOR"
if EDITOR="$BAD_EDITOR" "$PHOENIX" edit 2>/dev/null; then
    echo "FAIL: 'edit' should have failed on space-separated columns"
    exit 1
fi
[ "$(readlink -f "${RESURRECT_DIR}/last")" = "$SNAP_BEFORE_BAD_EDIT" ] || {
    echo "FAIL: Malformed 'edit' modified the 'last' symlink"
    exit 1
}

# 6. Verify pinned 'last' symlink protection when pruning to a smaller retention count
PINNED_SNAP=$(ls -1tr "${RESURRECT_DIR}"/tmux_resurrect_*.txt | head -n 1)
ln -sf "$(basename "$PINNED_SNAP")" "${RESURRECT_DIR}/last"
"$PHOENIX" prune 5
[ -f "$PINNED_SNAP" ] || { echo "FAIL: Pinned older snapshot was deleted by prune"; exit 1; }
[ "$(readlink -f "${RESURRECT_DIR}/last")" = "$PINNED_SNAP" ] || {
    echo "FAIL: 'last' no longer points to pinned snapshot"
    exit 1
}

# 7. Verify 'edit' rejects an empty WORKING_DIRECTORY column without touching 'last'
SNAP_BEFORE_EMPTY_DIR=$(readlink -f "${RESURRECT_DIR}/last")
EMPTY_DIR_EDITOR="${TMP_HOME}/empty_dir_editor.sh"
cat << 'EOF' > "$EMPTY_DIR_EDITOR"
#!/usr/bin/env bash
printf 'work:0.0\t\tpython3 missing_dir.py\n' > "$1"
EOF
chmod +x "$EMPTY_DIR_EDITOR"
if EDITOR="$EMPTY_DIR_EDITOR" "$PHOENIX" edit 2>/dev/null; then
    echo "FAIL: 'edit' should have failed on empty directory column"
    exit 1
fi
[ "$(readlink -f "${RESURRECT_DIR}/last")" = "$SNAP_BEFORE_EMPTY_DIR" ] || {
    echo "FAIL: Empty-directory 'edit' modified the 'last' symlink"
    exit 1
}

# 8. Verify 'edit' supports $EDITOR values containing flags/arguments
ARG_EDITOR="${TMP_HOME}/arg_editor.sh"
cat << 'EOF' > "$ARG_EDITOR"
#!/usr/bin/env bash
[ "$1" = "--flag" ] || exit 1
printf 'work:0.0\t/opt/jobs\techo with_args\n' > "$2"
EOF
chmod +x "$ARG_EDITOR"
EDITOR="${ARG_EDITOR} --flag" "$PHOENIX" edit
"$PHOENIX" list | grep -q "/opt/jobs" || { echo "FAIL: \$EDITOR with arguments did not update directory"; exit 1; }

# 9. Verify custom XDG_DATA_HOME snapshot directory resolution and pruning
CUSTOM_DATA_HOME="${TMP_HOME}/custom_data"
CUSTOM_RESURRECT="${CUSTOM_DATA_HOME}/tmux/resurrect"
mkdir -p "$CUSTOM_RESURRECT"
printf 'pane\tcustom\t0\t1\t:*\t0\tbash\t:/tmp\t1\tbash\t:\n' > "${CUSTOM_RESURRECT}/tmux_resurrect_20261114T090000.txt"
ln -sf "tmux_resurrect_20261114T090000.txt" "${CUSTOM_RESURRECT}/last"
XDG_DATA_HOME="$CUSTOM_DATA_HOME" "$PHOENIX" list | grep -q "custom:0.0" || {
    echo "FAIL: Custom XDG_DATA_HOME snapshot was not resolved"
    exit 1
}

# 10. Verify reconcile_tmux_conf cleans up boilerplate XDG duplicates and backs up conflicting custom XDG configs
# shellcheck source=../bin/tmux-phoenix
source "$PHOENIX"
mkdir -p "$(dirname "$XDG_CONF")"
printf 'set -g mouse on\n' > "$LEGACY_CONF"
printf '# comment\nset -g @plugin '\''tmux-plugins/tpm'\''\nset -g @plugin '\''tmux-plugins/tmux-sensible'\''\nrun '\''~/.tmux/plugins/tpm/tpm'\''\n' > "$XDG_CONF"
# Note: non-boilerplate plugin lines in XDG_CONF should be backed up to .bak rather than deleted
RESOLVED=$(reconcile_tmux_conf 2>/dev/null)
[ "$RESOLVED" = "$LEGACY_CONF" ] || { echo "FAIL: Expected $LEGACY_CONF, got $RESOLVED"; exit 1; }
[ ! -f "$XDG_CONF" ] && [ -f "${XDG_CONF}.bak" ] || { echo "FAIL: Conflicting XDG config was not backed up"; exit 1; }

rm -f "${XDG_CONF}.bak"
printf 'run '\''~/.tmux/plugins/tpm/tpm'\''\n' > "$XDG_CONF"
RESOLVED=$(reconcile_tmux_conf)
[ "$RESOLVED" = "$LEGACY_CONF" ] || { echo "FAIL: Expected $LEGACY_CONF after boilerplate removal"; exit 1; }
[ ! -e "$XDG_CONF" ] && [ ! -e "${XDG_CONF}.bak" ] || { echo "FAIL: Boilerplate XDG config was not removed cleanly"; exit 1; }

# 11. Verify 'setup' preserves active tmux sessions without stopping tmux.service (unless --restart)
(
    export TMUX_TMPDIR="${TMP_HOME}/tmux_tmp"
    mkdir -p "$TMUX_TMPDIR" "${TMP_HOME}/mock_bin"
    unset TMUX

    for repo in tpm tmux-resurrect tmux-continuum; do
        mkdir -p "${TMP_HOME}/.tmux/plugins/${repo}/scripts"
    done
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP_HOME}/.tmux/plugins/tpm/tpm"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP_HOME}/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    chmod +x "${TMP_HOME}/.tmux/plugins/tpm/tpm" "${TMP_HOME}/.tmux/plugins/tmux-resurrect/scripts/save.sh"

    SYSTEMCTL_LOG="${TMP_HOME}/systemctl.log"
    cat << EOF > "${TMP_HOME}/mock_bin/systemctl"
#!/usr/bin/env bash
echo "\$*" >> "$SYSTEMCTL_LOG"
exit 0
EOF
    cat << 'EOF' > "${TMP_HOME}/mock_bin/loginctl"
#!/usr/bin/env bash
echo "yes"
EOF
    cat << 'EOF' > "${TMP_HOME}/mock_bin/git"
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${TMP_HOME}/mock_bin/systemctl" "${TMP_HOME}/mock_bin/loginctl" "${TMP_HOME}/mock_bin/git"

    tmux new-session -d -s live_agent
    PATH="${TMP_HOME}/mock_bin:${PATH}" "$PHOENIX" setup >/dev/null

    tmux has-session -t live_agent 2>/dev/null || {
        echo "FAIL: Live tmux session was interrupted during setup"
        tmux kill-server 2>/dev/null || true
        exit 1
    }
    if grep -q -- "--user stop tmux.service" "$SYSTEMCTL_LOG"; then
        echo "FAIL: setup stopped tmux.service while real sessions were running"
        tmux kill-server 2>/dev/null || true
        exit 1
    fi
    grep -q -- "--user daemon-reload" "$SYSTEMCTL_LOG" || {
        echo "FAIL: setup did not reload systemd user daemon"
        tmux kill-server 2>/dev/null || true
        exit 1
    }
    grep -q -- "--user enable tmux.service" "$SYSTEMCTL_LOG" || {
        echo "FAIL: setup did not enable tmux.service"
        tmux kill-server 2>/dev/null || true
        exit 1
    }
    [ -f "${TMP_HOME}/.config/systemd/user/tmux.service" ] || {
        echo "FAIL: tmux.service unit file was not written"
        tmux kill-server 2>/dev/null || true
        exit 1
    }
    grep -q "# BEGIN TMUX-PHOENIX" "$LEGACY_CONF" || {
        echo "FAIL: Managed block missing in $LEGACY_CONF after setup"
        tmux kill-server 2>/dev/null || true
        exit 1
    }

    tmux kill-server 2>/dev/null || true
)

echo "All tests passed."
