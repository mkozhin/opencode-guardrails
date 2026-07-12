#!/usr/bin/env bash
#
# install.sh — install the opencode-guardrails agents and confirmation overlay.
#
# Two modes:
#   (default) global  — agents go into the always-loaded opencode global agent
#                       dir; the overlay lands in a separate OPENCODE_CONFIG_DIR
#                       drop-in whose activation command is PRINTED (a script
#                       cannot export an env var into your parent shell).
#   --project         — agents and the overlay go into ./.opencode/ (the project
#                       layer), which opencode loads automatically for this repo.
#
# The overlay makes guard-normal the default agent and disables the built-in
# build/plan agents. It is installed as a SEPARATE file/layer; your own opencode
# config is never edited.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_AGENTS_DIR="$SCRIPT_DIR/agents"
SRC_OVERLAY="$SCRIPT_DIR/opencode.json"

# opencode loads level agents from an "agent/" subdirectory (verified on
# opencode 1.17.18, both for the global config dir and for OPENCODE_CONFIG_DIR).
AGENT_SUBDIR="agent"

PROG="$(basename "$0")"

MODE="global"
FORCE=0

usage() {
    cat <<EOF
Usage: $PROG [--project] [--force] [-h|--help]

Install the opencode-guardrails agents and confirmation overlay.

Options:
  --project   Install into ./.opencode/ (project layer) instead of the global
              opencode config. The overlay then applies automatically for this
              project, with no env var to export.
  --force     Overwrite pre-existing files that differ from ours. Without it,
              differing files are left untouched and reported.
  -h, --help  Show this help and exit.

Default (no --project): agents are copied into the global opencode agent dir and
the overlay is placed in a drop-in directory; the exact activation command is
printed at the end.
EOF
}

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }

# shell_squote VALUE — print VALUE wrapped in single quotes, safe to paste into a
# shell. Embedded single quotes are escaped as '\'' so the result survives any
# path (spaces, $, backticks, quotes). Used for the printed activation commands.
shell_squote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# reject_irregular_dest DST — fail (setting REFUSED) if DST exists but is not a
# plain regular file: a symlink (cp would clobber its TARGET, possibly outside the
# install dir) or a directory/other (cp would silently write inside it and report
# success). Returns 0 and leaves REFUSED untouched when DST is a regular file or
# absent, so the caller may proceed.
reject_irregular_dest() {
    local dst="$1"
    if [ -L "$dst" ]; then
        err "destination is a symlink; refusing to follow it (its target would be overwritten): $dst"
        REFUSED=1
        return 1
    fi
    if [ -e "$dst" ] && [ ! -f "$dst" ]; then
        err "destination exists but is not a regular file (directory or special): $dst"
        REFUSED=1
        return 1
    fi
    return 0
}

# atomic_install SRC DST — copy SRC into a temp file in DST's OWN directory, then
# rename it over DST. `mv` replaces the directory entry atomically and never
# follows a symlink sitting at DST, so a symlink swapped in during the window
# between reject_irregular_dest and the write cannot be dereferenced to clobber
# its target. This closes the TOCTOU that a plain `rm -f; cp` or a bare `cp`
# (both of which dereference a symlinked DST) would leave open.
atomic_install() {
    local src="$1" dst="$2" dir tmp
    dir="$(dirname -- "$dst")"
    tmp="$(mktemp "$dir/.guardrails-install.XXXXXX")" || return 1
    if ! cp -- "$src" "$tmp"; then
        rm -f -- "$tmp"
        return 1
    fi
    # Match a normal `cp` result (respect umask) rather than mktemp's 0600, so
    # installed files are not surprisingly private.
    chmod +r -- "$tmp"
    mv -f -- "$tmp" "$dst"
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

# Validate source layout.
if [ ! -d "$SRC_AGENTS_DIR" ]; then
    err "source agents directory not found: $SRC_AGENTS_DIR"
    exit 1
fi
# shellcheck disable=SC2012
if ! ls "$SRC_AGENTS_DIR"/*.md >/dev/null 2>&1; then
    err "no agent files (*.md) found in: $SRC_AGENTS_DIR"
    exit 1
fi
if [ ! -f "$SRC_OVERLAY" ]; then
    err "source overlay not found: $SRC_OVERLAY"
    exit 1
fi

REFUSED=0

# install_file SRC DST
#   Idempotent copy: identical -> skip; differing -> overwrite only with --force,
#   otherwise leave the existing file in place and flag a refusal.
install_file() {
    local src="$1" dst="$2"
    reject_irregular_dest "$dst" || return 0
    if [ -f "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            log "  unchanged: $dst"
            return 0
        fi
        if [ "$FORCE" -eq 1 ]; then
            atomic_install "$src" "$dst"
            log "  overwritten: $dst"
            return 0
        fi
        warn "  refused: $dst already exists and differs (use --force to overwrite)"
        REFUSED=1
        return 0
    fi
    atomic_install "$src" "$dst"
    log "  installed: $dst"
}

install_agents() {
    local dest_dir="$1"
    mkdir -p "$dest_dir"
    log "Installing agents into: $dest_dir"
    local f
    for f in "$SRC_AGENTS_DIR"/*.md; do
        install_file "$f" "$dest_dir/$(basename "$f")"
    done
}

if [ "$MODE" = "global" ]; then
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        CONFIG_BASE="$XDG_CONFIG_HOME"
    elif [ -n "${HOME:-}" ]; then
        CONFIG_BASE="$HOME/.config"
    else
        err "cannot determine config dir: neither XDG_CONFIG_HOME nor HOME is set"
        exit 1
    fi
    AGENTS_DEST="$CONFIG_BASE/opencode/$AGENT_SUBDIR"
    OVERLAY_DIR="$CONFIG_BASE/opencode-guardrails"
    OVERLAY_DEST="$OVERLAY_DIR/opencode.json"

    install_agents "$AGENTS_DEST"

    mkdir -p "$OVERLAY_DIR"
    log "Installing overlay into drop-in directory: $OVERLAY_DIR"
    install_file "$SRC_OVERLAY" "$OVERLAY_DEST"

    log ""
    if [ "$REFUSED" -eq 1 ]; then
        warn "Some files were left untouched because they differ. Re-run with --force to overwrite."
    fi
    log "Agents installed. They load automatically from the global opencode config."
    log ""
    if [ -n "${OPENCODE_CONFIG_DIR:-}" ] && [ "${OPENCODE_CONFIG_DIR}" != "$OVERLAY_DIR" ]; then
        warn "WARNING: OPENCODE_CONFIG_DIR is already set to a different path:"
        warn "    OPENCODE_CONFIG_DIR=$OPENCODE_CONFIG_DIR"
        warn "Exporting the command below REPLACES it (opencode reads a single"
        warn "OPENCODE_CONFIG_DIR). If you need both, merge their contents into one"
        warn "directory instead of overwriting the variable."
        warn ""
    fi
    # Escape the path for safe copy-paste (spaces, $, quotes, backticks). OVERLAY_Q
    # is the single-quoted activation statement; OVERLAY_ECHO wraps that statement
    # again so the printed `echo …` appends a correctly-quoted line to the profile.
    OVERLAY_Q="$(shell_squote "$OVERLAY_DIR")"
    OVERLAY_ECHO="$(shell_squote "export OPENCODE_CONFIG_DIR=$OVERLAY_Q")"
    log "To ACTIVATE the overlay (guard-normal as default, build/plan disabled),"
    log "export OPENCODE_CONFIG_DIR so opencode loads the drop-in as an extra layer:"
    log ""
    log "    export OPENCODE_CONFIG_DIR=$OVERLAY_Q"
    log ""
    log "To make it permanent, add that line to your shell profile, e.g.:"
    log "    echo $OVERLAY_ECHO >> ~/.bashrc"
    log ""
    log "This script does NOT edit your shell profile and does NOT claim the overlay"
    log "is active yet — the export above must run in your own shell."
    log ""
    log "PRECEDENCE CAVEAT: a project opencode.json (./.opencode/opencode.json or"
    log "./opencode.json) sits in a HIGHER layer than this drop-in and will override"
    log "default_agent and re-enable build/plan for that project. Use --project there."
    log ""
    log "FALLBACK (agents only): if you never export OPENCODE_CONFIG_DIR, the three"
    log "guard-* agents are still installed and selectable, but build/plan stay in the"
    log "Tab cycle and guard-normal is NOT the default."
else
    PROJECT_DIR="$PWD/.opencode"
    AGENTS_DEST="$PROJECT_DIR/$AGENT_SUBDIR"
    OVERLAY_DEST="$PROJECT_DIR/opencode.json"

    install_agents "$AGENTS_DEST"

    mkdir -p "$PROJECT_DIR"
    log "Installing overlay into project layer: $OVERLAY_DEST"
    if ! reject_irregular_dest "$OVERLAY_DEST"; then
        :  # refused: not a regular file (symlink/dir); REFUSED already set
    elif [ -f "$OVERLAY_DEST" ]; then
        if cmp -s "$SRC_OVERLAY" "$OVERLAY_DEST"; then
            log "  unchanged: $OVERLAY_DEST"
        elif [ "$FORCE" -eq 1 ]; then
            atomic_install "$SRC_OVERLAY" "$OVERLAY_DEST"
            log "  overwritten: $OVERLAY_DEST"
        else
            warn "  refused: $OVERLAY_DEST already exists and differs."
            warn "  Not clobbering your project config. Merge these keys by hand:"
            warn '      "default_agent": "guard-normal",'
            warn '      "agent": { "build": { "disable": true }, "plan": { "disable": true } }'
            warn "  Or re-run with --force to replace the file entirely."
            REFUSED=1
        fi
    else
        atomic_install "$SRC_OVERLAY" "$OVERLAY_DEST"
        log "  installed: $OVERLAY_DEST"
    fi

    log ""
    if [ "$REFUSED" -eq 1 ]; then
        warn "Some files were left untouched because they differ. See the notes above."
    fi
    log "Installed into the project layer. The overlay applies automatically for this"
    log "project (project layer wins over the global/custom layers) — no env var needed."
fi

if [ "$REFUSED" -eq 1 ]; then
    exit 3
fi
exit 0
