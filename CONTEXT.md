# CONTEXT — Ubiquitous Language

Glossary for `opencode-guardrails`. Terms only — no implementation details.

## Threat model

- **Careless agent (in scope, "model A")** — the LLM doing normal work that
  *accidentally* reads a secret or runs a destructive command, with no intent to
  evade the guardrails. This is the sole adversary the product defends against.
- **Adversary / prompt-injection (out of scope, "model B")** — a hostile instruction
  that *actively* tries to exfiltrate secrets or cause damage and will obfuscate to
  bypass patterns. Explicitly NOT defended against: config-level patterns cannot form
  a security boundary. Real defense requires an OS-level sandbox, obtained by
  *composition* (documented in the README "Hardening" section), not by this tool.

## Core concepts

- **Level** — a named strictness setting for confirmations, realised as an opencode
  *primary agent*. Three exist: `guard-strict`, `guard-normal`, `guard-loose`.
- **Permission resolution** — the rule by which opencode turns a tool call + a set of
  glob patterns into an `allow`/`ask`/`deny` decision: **last-match-wins** (the last
  matching pattern in insertion order wins). The matcher is an anchored dotall regex
  (`^…$`, `*`→`.*`, `?`→`.`), so **`*` crosses `/`** — one `*.pem` matches both
  `app.pem` and `nested/app.pem`. The whole floor
  design depends on it. We do NOT ship a resolver — opencode owns the real one; our
  test suite models it in a documented `resolve()` **helper** inside `test_agents.py`
  (a model of opencode's semantics, explicitly not an authoritative resolver). It is a
  single helper, not a separate module — there is only one consumer, so the seam is
  hypothetical, not real.
- **Floor** — the set of rules that cannot be weakened by switching levels; they are
  appended last so last-match-wins makes them override a level's `allow`. Two tiers on
  the `read` tool plus a best-effort `bash` set (see below). Not "always ask" — hard
  secrets are denied outright.
- **Hard secrets (deny tier)** — the strongest floor rules, applied to `read` and
  **anchored, not substring** (a broad `*credentials*` would falsely deny
  `credentials-guide.md`). Because the matcher's `*` crosses `/`, a single extension
  pattern (`*.env`, `*.pem`, `*.key`) already covers any depth. Extension-less basenames
  instead use an **anchored root + `*/name` nested pair** so the match is bound to a path
  segment, not a substring. The set: `.env`/`*.env`/`*.env.*`, `*.pem`, `*.key`, the SSH
  private keys `id_rsa`/`id_ed25519`/`id_ecdsa`/`id_dsa`, the plaintext credential files
  `.netrc`/`.pgpass`/`.git-credentials`, `credentials`/`credentials.*`,
  `secrets`/`secrets.*`, and the *contents* of a `credentials/`/`secrets/` directory
  (each with its `*/…` nested twin) resolve to `deny`. Chosen over `ask` because `deny`
  survives `--auto` (auto-approve suppresses `ask` but not `deny`) and because these
  files are rarely legitimately read. This **strengthens** opencode's built-in `.env`
  handling — whose default is `ask`, not `deny` — to a hard `deny`. Final list is
  validated through the `resolve()` model.
- **Hidden files (ask tier)** — the softer floor rules, applied to `read`: **dot-named**
  paths resolve to `ask` via `.*` (any path starting with a dot, e.g. `.gitignore`,
  `.eslintrc`, and — since `*` crosses `/` — `.git/config`) and `*/.*` (a dot-named
  segment anywhere below the root, e.g. `src/.gitignore`). Because `*` crosses `/`, this
  tier is broad: anything with a dot-leading segment prompts. Secrets that also match the
  deny patterns above still `deny` (deny is appended later, last-match-wins). Conditional:
  `--auto` or a session-level `always` approval can suppress the prompt.
- **dangerous_bash** — the *best-effort* floor set on the `bash` tool: matches common
  direct forms of dangerous commands and secret-reads. opencode matches *parsed*
  commands (not raw strings), and chaining/obfuscation bypasses it — meaningful
  against the careless agent, not the adversary.

## Distribution

- **Agent files** — the three `guard-*.md` files are **hand-written and committed
  directly** (no generator, no `src/`→`dist/` split). Rationale: only three files with
  an identical floor block that rarely changes; a codegen pipeline plus CI-commits-to-
  `main` would cost more than it saves. Drift between the three is prevented by an
  **invariant test** asserting the floor block is byte-identical and appears last in
  the `read`/`bash` blocks of all three files.
- **Overlay** — a small hand-written `opencode.json` holding only top-level config that
  cannot live in an agent `.md` frontmatter: `default_agent: guard-normal` and
  disabling the built-in `build`/`plan` agents.
- **Overlay application** — the overlay is applied via config layering: it lives in a
  drop-in directory pointed at by the **`OPENCODE_CONFIG_DIR`** env var, and opencode
  merges configs rather than replacing them, so the user's own `opencode.json` is never
  hand-edited. There is no `opencode config set` CLI command; a launch `--agent` flag is
  ephemeral, not persistent.
