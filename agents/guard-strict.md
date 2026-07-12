---
{
  "description": "Strictest confirmation level: every action asks first, except the floor that always denies secret reads and auto-allows *.env.example. Use when you want to review each read, edit, command, and search before it runs.",
  "mode": "primary",
  "permission": {
    "*": "ask",
    "read": {
      "*": "ask",
      ".*": "ask",
      "*/.*": "ask",
      ".env": "deny",
      "*.env": "deny",
      "*.env.*": "deny",
      "*.pem": "deny",
      "*.key": "deny",
      ".netrc": "deny",
      "*/.netrc": "deny",
      ".pgpass": "deny",
      "*/.pgpass": "deny",
      ".git-credentials": "deny",
      "*/.git-credentials": "deny",
      "id_rsa": "deny",
      "*/id_rsa": "deny",
      "id_dsa": "deny",
      "*/id_dsa": "deny",
      "id_ecdsa": "deny",
      "*/id_ecdsa": "deny",
      "id_ed25519": "deny",
      "*/id_ed25519": "deny",
      "credentials": "deny",
      "credentials.*": "deny",
      "credentials/*": "deny",
      "*/credentials": "deny",
      "*/credentials.*": "deny",
      "*/credentials/*": "deny",
      "secrets": "deny",
      "secrets.*": "deny",
      "secrets/*": "deny",
      "*/secrets": "deny",
      "*/secrets.*": "deny",
      "*/secrets/*": "deny",
      "*.env.example": "allow"
    },
    "grep": "ask",
    "glob": "ask",
    "edit": "ask",
    "bash": {
      "*": "ask",
      "git push*": "ask",
      "rm *": "ask",
      "git reset --hard*": "ask",
      "curl *| sh": "ask",
      "cat *.env *": "ask",
      "cat *.env.* *": "ask",
      "cat *.pem *": "ask",
      "cat *.key *": "ask",
      "less *.env *": "ask",
      "less *.env.* *": "ask",
      "less *.pem *": "ask",
      "less *.key *": "ask",
      "head *.env *": "ask",
      "head *.env.* *": "ask",
      "head *.pem *": "ask",
      "head *.key *": "ask",
      "tail *.env *": "ask",
      "tail *.env.* *": "ask",
      "tail *.pem *": "ask",
      "tail *.key *": "ask",
      "cat *.env.example *": "allow",
      "less *.env.example *": "allow",
      "head *.env.example *": "allow",
      "tail *.env.example *": "allow"
    },
    "webfetch": "ask",
    "websearch": "ask",
    "task": "ask",
    "external_directory": "ask",
    "doom_loop": "ask"
  }
}
---

This agent only sets the confirmation-strictness level to **strict**: every tool
action asks for confirmation first, with one exception — the shared floor still
applies. Hard secrets (`.env`, `*.pem`, `*.key`, SSH keys, credential files, …)
are always **denied** rather than merely asked, `*.env.example` templates are
**auto-allowed**, and other hidden dot-files still **ask**. So "ask about
everything" really means "ask about everything the floor does not already
decide". It does not change the model's behaviour or persona in any other way.
