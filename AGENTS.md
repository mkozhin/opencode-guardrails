# AGENTS.md

Guidance for AI coding agents (Claude Code and others) working in this repository.

## What this project is

`opencode-guardrails` is a distributable confirmation-strictness system for opencode
(three primary agents `ask` / `normal` / `trust` plus an
immovable floor). The full specification and task order live in `docs/plans/` — the
active plan is the single source of requirements; check it before implementing.

## Artifact model (critical)

- **The three `agents/*.md` level files (`ask`/`normal`/`trust`) and the `opencode.json` overlay are
  hand-written and committed directly.** There is NO generator and NO `src/`→`dist/`
  split — a codegen pipeline for three rarely-changing files is not worth its cost.
- **The floor is appended LAST** in each level's `read`/`bash` blocks (last-match-wins,
  confirmed by opencode docs). It must be **byte-identical across all three files** — an
  invariant test enforces this; keep the three in sync by hand when editing the floor.
- **Threat model = careless agent only.** The floor reduces *accidental* secret reads
  and destructive commands. It is NOT a security boundary against a hostile
  prompt-injection (config patterns can't be). See CONTEXT.md and the README
  "Hardening" section.

## Code and tests

- **Python stdlib only, zero dependencies** (`json`, `unittest`). Do not add
  third-party packages.
- Run tests: `python -m unittest discover tests`.

## Process

- Implementation follows the plan in `docs/plans/`. **Task 1 (spike on a real
  opencode) is a hard gate** for the few remaining unverified assumptions; do not start
  authoring the agent files until it clears (opencode is not installed on this machine).
- Commits (both project and CI) must carry **no Claude/Anthropic attribution** (no
  `Co-Authored-By: Claude`, no "Generated with Claude Code", etc.).
- **Backlog**: task tracking lives in `backlog.md`, managed with the `bl` CLI. Run
  `bl help` for commands; start with `bl v` to list available tasks before reviewing
  or implementing new ones.

## Language and documentation policy

- **All repository files are written in English** (code, comments, config, agent
  descriptions, commit messages, AGENTS.md/CLAUDE.md). Exception: working planning
  documents under `docs/plans/` may stay in the author's language.
- **User-facing documentation is bilingual**, one language per file, English as the
  primary: `README.md` (English) alongside `README_RU.md` (Russian). Same rule for any
  other doc — the base name is the English version, and the Russian version gets a
  `_RU` suffix (e.g. `CONTRIBUTING.md` + `CONTRIBUTING_RU.md`). Keep both in sync.
