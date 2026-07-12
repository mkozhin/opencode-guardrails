---
{
  "description": "Strictest confirmation level: every action asks first. Use when you want to review each read, edit, command, and search before it runs.",
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
      "curl *| sh": "ask"
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
action asks for confirmation first. It does not change the model's behaviour or
persona in any other way.
