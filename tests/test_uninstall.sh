#!/usr/bin/env bash
#
# test_uninstall.sh — behavioural tests for uninstall.sh.
#
# Pure bash + stdlib tools. Every case runs against throwaway HOME / project
# directories under mktemp -d, so the real ~/.config/opencode is never touched.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"
UNINSTALL="$REPO_ROOT/uninstall.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

check() {
    # check <description> <condition-exit-code>
    if [ "$2" -eq 0 ]; then pass "$1"; else fail "$1"; fi
}

# Isolated sandbox; never inherit the caller's real config.
WORK="$(mktemp -d)"
# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAKE_HOME="$WORK/home"
export HOME="$FAKE_HOME"
export XDG_CONFIG_HOME="$FAKE_HOME/.config"

OPENCODE_DIR="$XDG_CONFIG_HOME/opencode"
AGENT_DIR="$OPENCODE_DIR/agent"
GUARD_DIR="$AGENT_DIR/guard"
OVERLAY_DIR="$XDG_CONFIG_HOME/opencode-guardrails"

reset_home() { rm -rf "$FAKE_HOME"; mkdir -p "$FAKE_HOME"; }

# --- Case 1: GLOBAL uninstall keeps sibling agents --------------------------
reset_home
bash "$INSTALL" >/dev/null 2>&1
# Seed a foreign sibling agent in the parent agent/ dir.
printf 'foreign agent\n' > "$AGENT_DIR/other.md"
out="$(bash "$UNINSTALL" 2>&1)"; rc=$?
check "global: uninstall exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "global: agent/guard/ removed" \
    "$([ ! -e "$GUARD_DIR" ] && echo 0 || echo 1)"
check "global: overlay drop-in removed" \
    "$([ ! -e "$OVERLAY_DIR" ] && echo 0 || echo 1)"
check "global: sibling agent/other.md preserved" \
    "$([ -f "$AGENT_DIR/other.md" ] && echo 0 || echo 1)"
check "global: parent agent/ dir preserved (sibling keeps it)" \
    "$([ -d "$AGENT_DIR" ] && echo 0 || echo 1)"
check "global: notes about shell profile printed" \
    "$(printf '%s' "$out" | grep -qi 'OPENCODE_CONFIG_DIR' && echo 0 || echo 1)"

# --- Case 2: GLOBAL removes whole guard dir incl. renamed/extra files -------
reset_home
mkdir -p "$GUARD_DIR"
printf 'a\n' > "$GUARD_DIR/ask.md"
printf 'n\n' > "$GUARD_DIR/normal.md"
printf 't\n' > "$GUARD_DIR/trust.md"
printf 'x\n' > "$GUARD_DIR/EXTRA_renamed.md"
out="$(bash "$UNINSTALL" 2>&1)"; rc=$?
check "whole-dir: uninstall exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "whole-dir: guard/ dir gone entirely" \
    "$([ ! -e "$GUARD_DIR" ] && echo 0 || echo 1)"
check "whole-dir: EXTRA_renamed.md removed (by dir, not by filename)" \
    "$([ ! -e "$GUARD_DIR/EXTRA_renamed.md" ] && echo 0 || echo 1)"

# --- Case 3: --project mode -------------------------------------------------
reset_home
PROJECT="$WORK/project"
mkdir -p "$PROJECT"
( cd "$PROJECT" && bash "$INSTALL" --project >/dev/null 2>&1 )
out="$(cd "$PROJECT" && bash "$UNINSTALL" --project 2>&1)"; rc=$?
check "project: uninstall exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "project: ./.opencode/agent/guard removed" \
    "$([ ! -e "$PROJECT/.opencode/agent/guard" ] && echo 0 || echo 1)"
check "project: matching overlay removed" \
    "$([ ! -e "$PROJECT/.opencode/opencode.json" ] && echo 0 || echo 1)"

# --- Case 3b: --project leaves a DIFFERING overlay untouched (no --force) ----
reset_home
PROJECT2="$WORK/project2"
mkdir -p "$PROJECT2"
( cd "$PROJECT2" && bash "$INSTALL" --project >/dev/null 2>&1 )
printf '{ "mine": true }\n' > "$PROJECT2/.opencode/opencode.json"
out="$(cd "$PROJECT2" && bash "$UNINSTALL" --project 2>&1)"; rc=$?
check "project-diff: uninstall exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "project-diff: guard/ still removed" \
    "$([ ! -e "$PROJECT2/.opencode/agent/guard" ] && echo 0 || echo 1)"
check "project-diff: differing overlay LEFT untouched" \
    "$([ -f "$PROJECT2/.opencode/opencode.json" ] && echo 0 || echo 1)"
check "project-diff: report says left untouched" \
    "$(printf '%s' "$out" | grep -qi 'left untouched' && echo 0 || echo 1)"

# --- Case 3c: --project --force deletes a differing overlay ------------------
out="$(cd "$PROJECT2" && bash "$UNINSTALL" --project --force 2>&1)"; rc=$?
check "project-force: exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "project-force: differing overlay deleted with --force" \
    "$([ ! -e "$PROJECT2/.opencode/opencode.json" ] && echo 0 || echo 1)"

# --- Case 4: idempotency ----------------------------------------------------
reset_home
bash "$INSTALL" >/dev/null 2>&1
bash "$UNINSTALL" >/dev/null 2>&1
out="$(bash "$UNINSTALL" 2>&1)"; rc=$?
check "idempotent: second uninstall exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "idempotent: reports not found" \
    "$(printf '%s' "$out" | grep -qi 'not found' && echo 0 || echo 1)"

# --- Case 5: unknown flag ---------------------------------------------------
out="$(bash "$UNINSTALL" --bogus 2>&1)"; rc=$?
check "unknown flag: non-zero exit" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "unknown flag: usage printed" \
    "$(printf '%s' "$out" | grep -q 'Usage:' && echo 0 || echo 1)"

# --- Summary ----------------------------------------------------------------
printf '\n----------------------------------------\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
exit 0
