---
{
  "description": "Boldest confirmation level: almost everything runs without asking, including edits and shell commands. Secrets are still denied and dangerous shell commands still ask.",
  "mode": "primary",
  "permission": {
    "*": "allow",
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
    "edit": "allow",
    "bash": {
      "*": "allow",
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

This agent only sets the confirmation-strictness level to **loose**: almost
everything runs without asking, including edits and shell commands. The floor
still applies — secrets are denied and the dangerous-shell patterns still ask.
It does not change the model's behaviour or persona.
