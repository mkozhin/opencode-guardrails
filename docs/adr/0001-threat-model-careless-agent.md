# 1. Threat model is the careless agent, not the adversary

Status: Accepted

## Context

`opencode-guardrails` ships a permission configuration (agent `.md` files + an
overlay) that makes opencode ask/deny on secret reads and dangerous shell commands.
A permission layer like this can be aimed at two very different adversaries:

- **A — the careless agent.** The LLM, doing normal work, *accidentally* reads a
  secret or runs a destructive command. No intent to evade.
- **B — the adversary / prompt-injection.** A hostile instruction (in fetched web
  content, a file, an issue) *actively* tries to exfiltrate secrets or cause damage
  and will obfuscate to bypass any pattern.

The product's guarantees are asymmetric (strict only for `read`, best-effort for
`bash`/`grep`/`glob`), so which adversary we target determines whether that asymmetry
is acceptable or a false promise.

Config-level patterns cannot form a boundary against B:
- the shell is Turing-complete string manipulation, so any string/parsed-command
  matcher is bypassable (`c=cat; $c .env`, globbing, base64, `/proc/self/environ`,
  secrets already in the process env, …) — a blocklist always loses to a motivated
  actor;
- exfiltration channels are unbounded (curl/wget/nc/DNS/`git push`/package installs);
- the permission engine sees the command, not the intent.

Real defense against B requires an OS-level sandbox (namespaces/seccomp/landlock,
egress allowlist) — a different layer and a different project.

## Decision

Defend against **A only**. State this explicitly in the README and treat it as the
frame for every guarantee. Do not add bash patterns in pursuit of B: half-B delivers
the *illusion* of protection (worse than none, because it invites false confidence).
Offer B by **composition** — document, in a README "Hardening" section, how to run
opencode inside an OS sandbox for users who need it.

## Consequences

- The best-effort limits of the `bash`/`grep`/`glob` floor are honest and coherent,
  not embarrassing — they are out of scope by design.
- Marketing/claims must never imply protection against malicious injection.
- Hard secrets use `deny` (not `ask`) partly because `deny` survives `--auto`; this is
  still model-A hardening (a careless agent running in auto mode), not model-B defense.
- If a future maintainer wants real B defense, that is a separate sandboxing effort,
  not an extension of these config patterns.
