#!/usr/bin/env bash
#
# uninstall.sh — cleanly remove what install.sh installs.
#
# Two modes (mirroring install.sh):
#   (default) global  — remove the level agents from the global opencode agent
#                       dir and the overlay drop-in directory.
#   --project         — remove the level agents and (if it is ours) the overlay
#                       from ./.opencode/.
#
# It removes the WHOLE agent/guard/ directory (not individual filenames), so a
# renamed or newly added agent inside it is still cleaned up. Sibling agents in
# the parent agent/ directory are never touched.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_OVERLAY="$SCRIPT_DIR/opencode.json"

# These MUST stay in sync with install.sh: the level agents install into
# "<config>/opencode/agent/guard" (global) or "./.opencode/agent/guard"
# (project). Grouping them under one namespace subdir lets uninstall remove the
# whole directory in one shot.
AGENT_SUBDIR="agent"
AGENT_NS="guard"

# Basename of the overlay drop-in directory that install.sh creates in global
# mode ("<config>/opencode-guardrails"). Guarded on removal.
OVERLAY_DROPIN_NAME="opencode-guardrails"

PROG="$(basename "$0")"

MODE="global"
FORCE=0

usage() {
    cat <<EOF
Usage: $PROG [--project] [--force] [-h|--help]

Remove what install.sh installed: the level agents and the confirmation overlay.

Options:
  --project   Uninstall from ./.opencode/ (project layer) instead of the global
              opencode config.
  --force     In --project mode, also delete a project overlay that DIFFERS from
              ours (by default a differing overlay is left untouched).
  -h, --help  Show this help and exit.

The whole agent/guard/ directory is removed (surviving renames/new files inside),
but sibling agents in the parent agent/ directory are never touched.
EOF
}

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }

# safe_rm_ns DIR — remove the level-agents namespace directory, but ONLY when the
# path really ends in ".../<AGENT_SUBDIR>/<AGENT_NS>" (i.e. .../agent/guard). This
# guards against a catastrophic `rm -rf` if a base variable is empty/unset (e.g.
# an empty CONFIG_BASE would otherwise yield "/opencode/agent/guard"). Reports and
# returns 0 when DIR is absent (idempotent).
safe_rm_ns() {
    local dir="$1"
    if [ -z "${dir:-}" ]; then
        err "internal: refusing to remove an empty/unset path"
        return 1
    fi
    if [ "$(basename "$dir")" != "$AGENT_NS" ] \
        || [ "$(basename "$(dirname "$dir")")" != "$AGENT_SUBDIR" ]; then
        err "refusing to remove unexpected path (not .../$AGENT_SUBDIR/$AGENT_NS): $dir"
        return 1
    fi
    if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
        log "  not found (nothing to remove): $dir"
        return 0
    fi
    rm -rf -- "$dir"
    log "  removed: $dir"
}

# safe_rm_dropin DIR — remove the overlay drop-in directory, but ONLY when its
# basename is exactly "$OVERLAY_DROPIN_NAME". Same empty-path guard as above.
# Reports and returns 0 when DIR is absent (idempotent).
safe_rm_dropin() {
    local dir="$1"
    if [ -z "${dir:-}" ]; then
        err "internal: refusing to remove an empty/unset path"
        return 1
    fi
    if [ "$(basename "$dir")" != "$OVERLAY_DROPIN_NAME" ]; then
        err "refusing to remove unexpected path (basename not $OVERLAY_DROPIN_NAME): $dir"
        return 1
    fi
    if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
        log "  not found (nothing to remove): $dir"
        return 0
    fi
    rm -rf -- "$dir"
    log "  removed: $dir"
}

# Parse arguments.
while [ "$#" -gt 0 ]; do
    case "$1" in
        --project) MODE="project" ;;
        --force)   FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            err "unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$MODE" = "global" ]; then
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        CONFIG_BASE="$XDG_CONFIG_HOME"
    elif [ -n "${HOME:-}" ]; then
        CONFIG_BASE="$HOME/.config"
    else
        err "cannot determine config dir: neither XDG_CONFIG_HOME nor HOME is set"
        exit 1
    fi
    AGENTS_DEST="$CONFIG_BASE/opencode/$AGENT_SUBDIR/$AGENT_NS"
    AGENT_PARENT="$CONFIG_BASE/opencode/$AGENT_SUBDIR"
    OVERLAY_DIR="$CONFIG_BASE/$OVERLAY_DROPIN_NAME"

    log "Removing level agents: $AGENTS_DEST"
    safe_rm_ns "$AGENTS_DEST"

    log "Removing overlay drop-in: $OVERLAY_DIR"
    safe_rm_dropin "$OVERLAY_DIR"

    # Best-effort: drop the now-possibly-empty agent/ parent. rmdir only succeeds
    # if it is empty, so sibling agents keep it — safe to ignore failure.
    if rmdir "$AGENT_PARENT" 2>/dev/null; then
        log "  removed empty parent: $AGENT_PARENT"
    fi

    log ""
    log "Manual cleanup — activation you may have set up after install.sh that this"
    log "script does NOT touch (it never edits your shell profile or opencode config):"

    # 1) Shell-profile exports of OPENCODE_CONFIG_DIR (any shell — bash/zsh/fish).
    #    Read-only scan: report where it lives so you can remove it by hand.
    home="${HOME:-}"
    prof_found=0
    if [ -n "$home" ]; then
        for prof in "$home/.bashrc" "$home/.bash_profile" "$home/.profile" \
                    "$home/.zshrc" "$home/.zprofile" "$home/.zshenv" \
                    "$home/.config/fish/config.fish"; do
            [ -f "$prof" ] || continue
            if grep -n 'OPENCODE_CONFIG_DIR' "$prof" >/dev/null 2>&1; then
                prof_found=1
                warn "  - $prof exports OPENCODE_CONFIG_DIR — remove the line(s):"
                grep -n 'OPENCODE_CONFIG_DIR' "$prof" 2>/dev/null | sed 's/^/        /' >&2 || true
            fi
        done
    fi
    if [ "$prof_found" -eq 0 ]; then
        log "  - No OPENCODE_CONFIG_DIR export found in your common shell profiles."
    fi
    if [ -n "${OPENCODE_CONFIG_DIR:-}" ]; then
        warn "  - OPENCODE_CONFIG_DIR is set in THIS shell; run: unset OPENCODE_CONFIG_DIR"
    fi

    # 2) Keys merged by hand into the GLOBAL opencode config (the env-var-free path).
    cfg_found=0
    for cfg in "$CONFIG_BASE/opencode/opencode.json" "$CONFIG_BASE/opencode/opencode.jsonc"; do
        [ -f "$cfg" ] || continue
        if grep -q 'guard/normal' "$cfg" 2>/dev/null; then
            cfg_found=1
            warn "  - $cfg references guard/normal — you likely merged the overlay keys here."
        fi
    done
    if [ "$cfg_found" -eq 1 ]; then
        warn "    Remove by hand: \"default_agent\": \"guard/normal\", and the"
        warn "    \"agent\": { \"build\": { \"disable\": true }, \"plan\": { \"disable\": true } } entries."
    else
        log "  - No guard/normal keys found in your global opencode.json / opencode.jsonc."
    fi
else
    PROJECT_DIR="$PWD/.opencode"
    AGENTS_DEST="$PROJECT_DIR/$AGENT_SUBDIR/$AGENT_NS"
    AGENT_PARENT="$PROJECT_DIR/$AGENT_SUBDIR"
    OVERLAY_DEST="$PROJECT_DIR/opencode.json"

    log "Removing level agents: $AGENTS_DEST"
    safe_rm_ns "$AGENTS_DEST"

    log "Checking project overlay: $OVERLAY_DEST"
    if [ ! -e "$OVERLAY_DEST" ] && [ ! -L "$OVERLAY_DEST" ]; then
        log "  not found (nothing to remove): $OVERLAY_DEST"
    elif [ ! -f "$SRC_OVERLAY" ]; then
        # Cannot compare without our source overlay; be conservative.
        warn "  source overlay not found ($SRC_OVERLAY); leaving project overlay untouched: $OVERLAY_DEST"
    elif [ -f "$OVERLAY_DEST" ] && cmp -s "$SRC_OVERLAY" "$OVERLAY_DEST"; then
        rm -f -- "$OVERLAY_DEST"
        log "  removed: $OVERLAY_DEST"
    elif [ "$FORCE" -eq 1 ]; then
        rm -f -- "$OVERLAY_DEST"
        log "  removed (differs, --force): $OVERLAY_DEST"
    else
        warn "  left untouched: $OVERLAY_DEST differs from ours (may be your own/merged"
        warn "  config). Re-run with --force to delete it, or remove it by hand."
    fi

    # Best-effort: drop now-empty agent/ then .opencode/.
    if rmdir "$AGENT_PARENT" 2>/dev/null; then
        log "  removed empty parent: $AGENT_PARENT"
    fi
    if rmdir "$PROJECT_DIR" 2>/dev/null; then
        log "  removed empty parent: $PROJECT_DIR"
    fi

    log ""
    log "Manual cleanup: if you merged our keys ('default_agent', 'agent.build'/'plan')"
    log "into a pre-existing $OVERLAY_DEST that this script left untouched, remove them by"
    log "hand. --project needs no shell profile or env var, so nothing else to clean up."
fi

exit 0
