#!/usr/bin/env bash
#
# test_install.sh — behavioural tests for install.sh.
#
# Pure bash + stdlib tools. Every case runs against throwaway HOME / project
# directories under mktemp -d, so the real ~/.config/opencode is never touched.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"

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

AGENT_DEST="$XDG_CONFIG_HOME/opencode/agent"
OVERLAY_DIR="$XDG_CONFIG_HOME/opencode-guardrails"

# --- Case 1: global mode, clean HOME ---------------------------------------
reset_home() { rm -rf "$FAKE_HOME"; mkdir -p "$FAKE_HOME"; }
reset_home
out="$(bash "$INSTALL" 2>&1)"; rc=$?
check "global: exit 0 on clean install" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "global: guard-normal.md landed in agent/ dir" \
    "$([ -f "$AGENT_DEST/guard-normal.md" ] && echo 0 || echo 1)"
check "global: guard-strict.md landed in agent/ dir" \
    "$([ -f "$AGENT_DEST/guard-strict.md" ] && echo 0 || echo 1)"
check "global: guard-loose.md landed in agent/ dir" \
    "$([ -f "$AGENT_DEST/guard-loose.md" ] && echo 0 || echo 1)"
check "global: overlay placed in drop-in dir" \
    "$([ -f "$OVERLAY_DIR/opencode.json" ] && echo 0 || echo 1)"
check "global: export command printed" \
    "$(printf '%s' "$out" | grep -q 'export OPENCODE_CONFIG_DIR=' && echo 0 || echo 1)"
check "global: precedence caveat printed" \
    "$(printf '%s' "$out" | grep -qi 'PRECEDENCE CAVEAT' && echo 0 || echo 1)"
check "global: agents-only fallback documented" \
    "$(printf '%s' "$out" | grep -qi 'FALLBACK' && echo 0 || echo 1)"

# --- Case 2: idempotent re-run ---------------------------------------------
out="$(bash "$INSTALL" 2>&1)"; rc=$?
check "global: re-run exits 0 (idempotent)" \
    "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "global: re-run reports files unchanged" \
    "$(printf '%s' "$out" | grep -q 'unchanged:' && echo 0 || echo 1)"
# Exactly three agent files, no duplicates/corruption.
n_agents="$(find "$AGENT_DEST" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
check "global: exactly 3 agent files after re-run" \
    "$([ "$n_agents" -eq 3 ] && echo 0 || echo 1)"

# --- Case 3: project mode ---------------------------------------------------
reset_home
PROJECT="$WORK/project"
mkdir -p "$PROJECT"
out="$(cd "$PROJECT" && bash "$INSTALL" --project 2>&1)"; rc=$?
check "project: exit 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "project: reports files installed" \
    "$(printf '%s' "$out" | grep -q 'installed:' && echo 0 || echo 1)"
check "project: agents in ./.opencode/agent/" \
    "$([ -f "$PROJECT/.opencode/agent/guard-normal.md" ] && echo 0 || echo 1)"
check "project: overlay in ./.opencode/opencode.json" \
    "$([ -f "$PROJECT/.opencode/opencode.json" ] && echo 0 || echo 1)"
check "project: overlay matches source" \
    "$(cmp -s "$REPO_ROOT/opencode.json" "$PROJECT/.opencode/opencode.json" && echo 0 || echo 1)"

# --- Case 4: pre-existing different agent file without --force --------------
reset_home
mkdir -p "$AGENT_DEST"
printf 'DIFFERENT USER CONTENT\n' > "$AGENT_DEST/guard-normal.md"
out="$(bash "$INSTALL" 2>&1)"; rc=$?
check "conflict: non-zero exit when a differing file is present" \
    "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "conflict: existing file NOT clobbered without --force" \
    "$(grep -q 'DIFFERENT USER CONTENT' "$AGENT_DEST/guard-normal.md" && echo 0 || echo 1)"
check "conflict: refusal reported" \
    "$(printf '%s' "$out" | grep -qi 'refused' && echo 0 || echo 1)"
# The other, non-conflicting agents should still install.
check "conflict: non-conflicting agent still installed" \
    "$([ -f "$AGENT_DEST/guard-strict.md" ] && echo 0 || echo 1)"

# --- Case 5: --force overwrites --------------------------------------------
out="$(bash "$INSTALL" --force 2>&1)"; rc=$?
check "force: exit 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
check "force: reports differing file overwritten" \
    "$(printf '%s' "$out" | grep -q 'overwritten:' && echo 0 || echo 1)"
check "force: differing file overwritten with ours" \
    "$(cmp -s "$REPO_ROOT/agents/guard-normal.md" "$AGENT_DEST/guard-normal.md" && echo 0 || echo 1)"

# --- Case 6: unknown flag ---------------------------------------------------
reset_home
out="$(bash "$INSTALL" --bogus 2>&1)"; rc=$?
check "unknown flag: non-zero exit" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "unknown flag: usage printed" \
    "$(printf '%s' "$out" | grep -q 'Usage:' && echo 0 || echo 1)"

# --- Case 7: missing agents/ source dir ------------------------------------
reset_home
FAKE_REPO="$WORK/fakerepo"
mkdir -p "$FAKE_REPO"
cp "$INSTALL" "$FAKE_REPO/install.sh"
cp "$REPO_ROOT/opencode.json" "$FAKE_REPO/opencode.json"
out="$(bash "$FAKE_REPO/install.sh" 2>&1)"; rc=$?
check "missing agents dir: non-zero exit" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)"
check "missing agents dir: clear error" \
    "$(printf '%s' "$out" | grep -qi 'agents directory not found' && echo 0 || echo 1)"

# --- Summary ----------------------------------------------------------------
printf '\n----------------------------------------\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
exit 0
