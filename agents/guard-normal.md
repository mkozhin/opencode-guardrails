---
{
  "description": "Balanced default confirmation level: reads and searches flow, while edits and shell commands ask first. Secrets are always denied and other hidden files still ask.",
  "mode": "primary",
  "permission": {
    "*": "ask",
    "read": {
      "*": "allow",
      ".*": "ask",
      "*/.*": "ask",
      ".env": "deny",
      "*.env": "deny",
      "*.env.*": "deny",
      "*.pem": "deny",
      "*.key": "deny",
      "id_rsa": "deny",
      "*/id_rsa": "deny",
      "credentials": "deny",
      "credentials.*": "deny",
      "*/credentials": "deny",
      "*/credentials.*": "deny",
      "secrets": "deny",
      "secrets.*": "deny",
      "*/secrets": "deny",
      "*/secrets.*": "deny",
      "*.env.example": "allow"
    },
    "grep": "allow",
    "glob": "allow",
    "edit": "ask",
    "bash": {
      "*": "ask",
      "git push*": "ask",
      "rm *": "ask",
      "git reset --hard*": "ask",
      "curl *| sh": "ask"
    },
    "webfetch": "allow",
    "websearch": "allow",
    "task": "ask",
    "external_directory": "ask",
    "doom_loop": "ask"
  }
}
---

This agent only sets the confirmation-strictness level to **normal** (the
default): reads and searches flow freely, while edits and shell commands ask for
confirmation. The secret floor still applies — secrets are denied and other
hidden files ask. It does not change the model's behaviour or persona.
