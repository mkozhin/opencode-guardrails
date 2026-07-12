> Русская версия: [README_RU.md](README_RU.md)

# opencode-guardrails

A distributable **confirmation-strictness system** for [opencode](https://opencode.ai).
It replaces the built-in `build`/`plan` pair with a single strictness switch: three
primary agents you cycle with **Tab** — from "ask about everything" to "run almost
anything" — plus an immovable floor that keeps secrets and a handful of dangerous
shell commands guarded at every level.

## Purpose

opencode ships two primary agents (`build`, `plan`) that mix *what the model does*
with *how much it asks*. This project narrows that down to one axis — **how strict the
confirmations are** — and exposes it as three interchangeable agents:

| Agent          | Meaning                                                              |
|----------------|---------------------------------------------------------------------|
| `guard-strict` | Every action asks first. Review each read, edit, command, search.   |
| `guard-normal` | Balanced default. Reads/searches flow; edits and shell ask.         |
| `guard-loose`  | Boldest. Almost everything runs; secrets and dangerous shell guard. |

They are ordinary opencode primary agents, so they appear in the **Tab** cycle. The
overlay (see [Installation](#installation)) makes `guard-normal` the default and hides
`build`/`plan`, so the Tab cycle becomes exactly these three levels. None of them
change the model's behaviour or persona — they set **only** the confirmation level.

## Levels

Each level is a matrix of opencode permissions (`allow` / `ask` / `deny`) over the
tools. The catch-all `"*"` is set explicitly per level; specific tools override it.

| Tool                              | strict | normal (default) | loose |
|-----------------------------------|:------:|:----------------:|:-----:|
| `"*"` (catch-all)                 | ask    | ask              | allow |
| `read`                            | ask †  | allow †          | allow † |
| `grep` / `glob`                   | ask    | allow ‡          | allow ‡ |
| `edit`                            | ask    | ask              | allow |
| `bash`                            | ask ✦  | ask ✦            | allow ✦ |
| `webfetch` / `websearch`          | ask    | allow            | allow |
| `task`                            | ask    | ask              | ask   |
| `external_directory` / `doom_loop`| ask    | ask              | ask   |

† `read` is subject to the **floor** (below): even where `read` is `allow`, hard
secrets are forced to `deny` and other hidden files to `ask`.
‡ `grep`/`glob` permissions match the *search pattern*, not file paths, so the floor
cannot apply to them — see [Known limitations](#known-limitations).
✦ `bash` always keeps the best-effort dangerous-command floor (below).

### The floor

The floor is a fixed block of rules **appended last** in every level's `read`/`bash`
config. opencode resolves permissions **last-match-wins**, so appending the floor last
makes it override a level's `allow`. The block is **byte-identical across all three
agent files** (an invariant test enforces this).

- **Hard secrets → `deny` (on `read`).** `.env` / `*.env` / `*.env.*`, `*.pem`,
  `*.key`, the SSH private keys `id_rsa` / `id_ed25519` / `id_ecdsa` / `id_dsa`, the
  plaintext credential files `.netrc` / `.pgpass` / `.git-credentials`,
  `credentials` / `credentials.*`, `secrets` / `secrets.*`, and the *contents* of a
  `credentials/` or `secrets/` directory (each with its nested `*/…` twin) resolve to
  `deny`. `deny` is used instead of `ask` because it **survives `--auto`** (auto-approve
  suppresses `ask`, but not `deny`), and because these files are rarely legitimately
  read. This **strengthens** opencode's built-in `.env` handling — whose default is
  `ask`, not `deny` — to a hard `deny`. Patterns are **anchored, not substring**, so
  ordinary docs like `credentials-guide.md` or `secrets-overview.md` are *not* denied.
  A carve-out for `*.env.example` (appended last) keeps templates readable. Because the
  floor is byte-identical across levels, both the `deny` tier and this carve-out apply
  even on `strict`: hard secrets are denied and `.env.example` is auto-allowed at every
  level, so `strict`'s "ask about everything" is really "ask about everything the floor
  does not already decide".
- **Other hidden files → `ask` (on `read`).** Dot-named files (`.*`, `*/.*`, e.g.
  `.gitignore`, `.eslintrc`) prompt for confirmation. This tier is *conditional*:
  `--auto` or a session-level `always` approval can suppress the prompt.
- **Dangerous bash → `ask` (best-effort).** Common direct forms — `git push*`,
  `rm *`, `git reset --hard*`, `curl … | sh` — plus best-effort secret **reads**
  through the shell (`cat` / `less` / `head` / `tail` of `*.env` / `*.env.*` /
  `*.pem` / `*.key`, e.g. `cat .env`) — prompt even on `loose`. This is
  best-effort only: chaining, variables and obfuscation bypass it (`c=cat; $c .env`),
  and it covers the four common readers on the env/pem/key file classes, not every
  reader or every secret name (see [Known limitations](#known-limitations)).

## Threat model — the careless agent only

**This tool defends against exactly one adversary: the careless agent (model A).**

- **A — the careless agent (in scope).** The LLM, doing normal work, *accidentally*
  reads a secret or runs a destructive command. No intent to evade. The floor reduces
  these accidents.
- **B — the adversary / prompt-injection (out of scope).** A hostile instruction (in
  fetched web content, a file, an issue) that *actively* tries to exfiltrate secrets or
  cause damage, and will obfuscate to bypass any pattern.

**opencode-guardrails is NOT a security boundary against B.** Config-level patterns
cannot be one: the shell is Turing-complete, so any string/parsed-command matcher is
bypassable (`c=cat; $c .env`, base64, `/proc/self/environ`, secrets already in the
process env, …), and exfiltration channels are unbounded. The permission engine sees
the command, not the intent. Claiming half-defense against B would be worse than none —
it invites false confidence.

Full rationale: [docs/adr/0001-threat-model-careless-agent.md](docs/adr/0001-threat-model-careless-agent.md).

## Hardening

If you need protection against **malicious/injected** instructions (model B), do not
rely on these guardrails. Get real defense by **composition**: run opencode inside an
**OS-level sandbox** — Linux namespaces / seccomp / Landlock, a container, or a VM —
with a filesystem allowlist and restricted network egress. That is a separate layer
which actually contains a hostile process; the guardrails then reduce *accidental*
mistakes on top of it, but they are not themselves the boundary.

## Installation

Requires a working opencode install (see [Compatibility](#compatibility)). Clone this
repo, then run `install.sh` from its root.

### Primary path — global install + overlay via `OPENCODE_CONFIG_DIR`

```sh
./install.sh
```

This copies the three `guard-*.md` files into your global opencode agent directory
(`${XDG_CONFIG_HOME:-~/.config}/opencode/agent/`, from which opencode always loads
them) and places the [`opencode.json`](opencode.json) overlay into a separate drop-in
directory (`${XDG_CONFIG_HOME:-~/.config}/opencode-guardrails/`).

The overlay (`default_agent: guard-normal` + disabling `build`/`plan`) is activated by
pointing opencode at that drop-in directory with **`OPENCODE_CONFIG_DIR`**. A script
**cannot** export an env var into your parent shell, so `install.sh` **prints the exact
command** instead:

```sh
export OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode-guardrails"
# make it permanent:
echo 'export OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode-guardrails"' >> ~/.bashrc
```

The drop-in directory is `${XDG_CONFIG_HOME:-$HOME/.config}/opencode-guardrails`, so if
you set `XDG_CONFIG_HOME` this path follows it — copy the **exact command
`install.sh` prints** rather than hardcoding `~/.config`.

opencode *merges* config layers rather than replacing them, so this adds the overlay on
top of your global config without editing anything you own.

**Precedence caveat.** The overlay lands in the *custom* layer, and the layer order is
`remote → global → custom → project`. A **project** `opencode.json`
(`./opencode.json` or `./.opencode/opencode.json`) therefore **overrides** the overlay:
it can win back `default_agent` and re-enable `build`/`plan` for that project. In such a
project, use `--project` instead.

### `--project` mode

```sh
./install.sh --project
```

Writes the agents into `./.opencode/agent/` and the overlay into
`./.opencode/opencode.json` — the **project layer**, which wins over global/custom, so
the overlay applies automatically for that project with **no env var to export**. If a
project `opencode.json` already exists and differs, the installer refuses to clobber it
and prints the keys to merge by hand (or re-run with `--force`).

### Fallback — agents only

If you never export `OPENCODE_CONFIG_DIR` (global mode), the three `guard-*` agents are
still installed and selectable — but **`build`/`plan` stay in the Tab cycle** and
`guard-normal` is **not** the default. This is a valid, lighter-touch setup; you just
switch to a level manually.

`install.sh` is idempotent, never overwrites a differing file without `--force`, and
prints all of the above (activation command, precedence caveat, fallback) at the end.

## Compatibility

- **Minimum supported = verified: opencode 1.17.18.**

All behaviour above (agent `disable` syntax, `default_agent`, `OPENCODE_CONFIG_DIR`
layering, the permission matcher semantics, `agent/` load directory) was verified
against opencode 1.17.18. Other versions may differ; the matcher and bash handling in
particular are version-sensitive (see below).

## Known limitations

Being honest about what the floor does **not** cover:

- **`grep` / `glob` do not honor the `read` secret-deny.** Their permission matches the
  *search pattern*, not the file paths returned, so a `grep` on `normal`/`loose` can
  surface secret contents. The strong `deny` guarantee applies to **`read` only**.
- **bash matching is whole-string, best-effort.** On 1.17.18 the bash permission
  matches the *entire command string* (the tree-sitter parser is not yet ported). So
  chains, variables and obfuscation bypass the patterns — `c=cat; $c .env`, `echo x | sh`,
  `foo && rm bar`, anything not starting with a literal matched prefix. This is exactly
  the model-A boundary, not a model-B defense.
- **`--auto` / session `always` suppress the `ask` tier.** They do **not** affect
  `deny` — hard secrets stay denied — but the "other hidden files → ask" tier and the
  dangerous-bash `ask` prompts can be suppressed. Guarantees for the ask tier are
  therefore conditional.
- **Project-config precedence.** As above, a project `opencode.json` overrides the
  custom/env overlay (`project > custom > global`), so the default-agent replacement is
  only guaranteed absent a conflicting project config. Use `--project` there.

## Repository layout

- [`agents/`](agents/) — the three hand-written level agents
  ([`guard-strict.md`](agents/guard-strict.md),
  [`guard-normal.md`](agents/guard-normal.md),
  [`guard-loose.md`](agents/guard-loose.md)). There is no generator; keep the floor in
  sync by hand.
- [`opencode.json`](opencode.json) — the overlay (`default_agent` + disable
  `build`/`plan`).
- [`install.sh`](install.sh) — installer for both modes.
- [`docs/adr/0001-threat-model-careless-agent.md`](docs/adr/0001-threat-model-careless-agent.md)
  — the threat-model decision.
- `tests/` — stdlib `unittest` suite. Run: `python3 -m unittest discover tests`.

## License

[MIT](LICENSE).
