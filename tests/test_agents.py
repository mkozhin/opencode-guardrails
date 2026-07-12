"""Artifact tests for opencode-guardrails (Task 3).

These tests were authored tests-first, BEFORE the three ``agents/guard-*.md``
files and the ``opencode.json`` overlay existed (Task 4). Those artifacts now
exist and the whole suite is green. The two test families are:

  * The ``resolve()`` model unit tests and the frontmatter/overlay validator
    error-case tests exercise the in-file helpers against hand-built fixtures,
    independent of the artifact files.
  * The order-invariant, real-path-matrix and real-artifact validity tests read
    the committed agent files and assert their behaviour.

Authoritative opencode semantics encoded here come from the Task 1 spike on a
live opencode 1.17.18 (see the plan's "Корректировки плана по итогам Task 1").
The single most important correction versus the original plan: opencode's
matcher is a plain anchored regex with ``*`` -> ``.*`` under the dotall flag,
so ``*`` CROSSES ``/``. One ``*.pem`` therefore matches both ``app.pem`` and
``nested/app.pem`` -- paired root+nested patterns are redundant.
"""

import json
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AGENTS_DIR = os.path.join(ROOT, "agents")
OVERLAY_PATH = os.path.join(ROOT, "opencode.json")
LEVELS = ("strict", "normal", "loose")


# ---------------------------------------------------------------------------
# resolve(): a MODEL of opencode's permission resolution -- NOT the authority.
# ---------------------------------------------------------------------------
#
# opencode's Wildcard.match is `new RegExp("^" + escaped + "$", "s")` where the
# pattern is transformed by: escape the regex-special chars `[.+^${}()|[\]\\]`,
# then `*` -> `.*` and `?` -> `.`, with the dotall (`s`) flag. `/` is NOT escaped
# and is NOT special, so `*` (`.*`) crosses `/`. A trailing ` *` collapses to
# `( .*)?` (this matters for bash patterns like `git push *`, not for read paths).
# Rule evaluation is `findLast(matching)` over insertion order; the default when
# nothing matches is `ask`.
#
# This helper models that matcher and resolution for the pattern classes we
# actually ship (globs with `*`/`?`, `/`, and regex-special chars). Our floor
# contains no backslashes and worktree-relative paths on POSIX contain none, so
# any input/pattern backslash normalization the real matcher may perform is out
# of scope here and deliberately not reproduced. It lives inside the test module
# on purpose: it has a single consumer (these tests), so a separate importable
# module would be over-engineering. It is a MODEL used to reason about
# the hand-written artifact -- the authoritative behaviour is opencode's own, and
# the runtime smoke-gate in Task 8 is what validates the model against reality.

_SPECIAL = re.compile(r"[.+^${}()|\[\]\\]")


def _pattern_to_regex(pattern):
    """Compile an opencode glob pattern to the same anchored dotall regex."""
    escaped = _SPECIAL.sub(lambda m: "\\" + m.group(0), pattern)
    body = escaped.replace("*", ".*").replace("?", ".")
    # opencode: a trailing ` *` (now ` .*`) becomes `( .*)?`.
    if body.endswith(" .*"):
        body = body[:-3] + "( .*)?"
    return re.compile("^" + body + "$", re.S)


def resolve(read_block, path):
    """Resolve a worktree-relative *path* against an ordered *read_block*.

    MODEL of opencode semantics (see module docstring), NOT the authoritative
    implementation. ``read_block`` is an ordered mapping of glob pattern ->
    permission ("allow"/"ask"/"deny"); the LAST matching rule wins; the default
    when nothing matches is ``"ask"``.
    """
    result = "ask"
    for pattern, permission in read_block.items():
        if _pattern_to_regex(pattern).match(path):
            result = permission
    return result


# ---------------------------------------------------------------------------
# Frontmatter / overlay validators.
# ---------------------------------------------------------------------------
#
# Task 1 fixed the frontmatter format: a JSON object written between the first
# pair of `---` fences (opencode parses it as YAML since JSON is a subset of
# YAML). Our validator extracts that text and parses it with stdlib json.loads
# -- zero dependencies, no YAML parser needed.


def extract_frontmatter_text(text):
    """Return the raw text between the first pair of ``---`` fences.

    Raises ValueError if the opening or closing fence is missing.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("missing opening '---' frontmatter fence")
    body = []
    for line in lines[1:]:
        if line.strip() == "---":
            return "\n".join(body)
        body.append(line)
    raise ValueError("missing closing '---' frontmatter fence")


def validate_frontmatter(text):
    """Parse and validate an agent .md frontmatter block.

    Returns the parsed dict on success. Raises ValueError (json.JSONDecodeError
    is a subclass) on malformed JSON or on a missing/invalid required key.
    """
    data = json.loads(extract_frontmatter_text(text))
    if not isinstance(data, dict):
        raise ValueError("frontmatter must be a JSON object")
    for key in ("description", "mode", "permission"):
        if key not in data:
            raise ValueError("missing required frontmatter key: %s" % key)
    if data["mode"] != "primary":
        raise ValueError("mode must be 'primary', got %r" % (data["mode"],))
    if not isinstance(data["permission"], dict):
        raise ValueError("permission must be a JSON object")
    return data


def validate_overlay(text):
    """Parse and validate the ``opencode.json`` overlay.

    Returns the parsed dict on success. Raises ValueError on malformed JSON, a
    missing/invalid ``default_agent``, or a missing/invalid ``agent`` disable map.
    """
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("overlay must be a JSON object")
    if not isinstance(data.get("default_agent"), str) or not data["default_agent"]:
        raise ValueError("overlay must set a non-empty string 'default_agent'")
    agent = data.get("agent")
    if not isinstance(agent, dict) or not agent:
        raise ValueError("overlay must contain an 'agent' disable map")
    # The overlay's whole purpose is to disable the built-in build/plan agents, so
    # each MUST be present with disable === true (boolean). A missing entry or a
    # `disable: false` would silently re-enable the agent and defeat the overlay.
    for name in ("build", "plan"):
        cfg = agent.get(name)
        if not isinstance(cfg, dict):
            raise ValueError("agent %r entry must be an object" % name)
        if cfg.get("disable") is not True:
            raise ValueError("agent %r must set disable = true (boolean)" % name)
    return data


# ---------------------------------------------------------------------------
# Artifact loaders (read the committed guard-*.md files).
# ---------------------------------------------------------------------------


def _read_guard(level):
    path = os.path.join(AGENTS_DIR, "guard-%s.md" % level)
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def load_guard_permission(level):
    return validate_frontmatter(_read_guard(level))["permission"]


# A representative anchored floor used by the resolve() unit tests. It encodes
# the shape the Task 4 floor must take under the corrected regex semantics:
# leading `*` for any-depth reach, ANCHORED forms for extension-less secret
# names (so doc files like `credentials-guide.md` are NOT falsely denied), and
# the `*.env.example` carve-out LAST so it overrides the deny. This is a local
# fixture, deliberately independent of the yet-unwritten agents.
_SAMPLE_FLOOR = {
    "*": "allow",
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
    "*.env.example": "allow",
}


# ===========================================================================
# GREEN: resolve() model unit tests.
# ===========================================================================


class TestResolveModel(unittest.TestCase):
    def test_last_match_wins_order(self):
        block = {"*": "allow", ".env": "deny"}
        self.assertEqual(resolve(block, ".env"), "deny")
        self.assertEqual(resolve(block, "foo.txt"), "allow")

    def test_default_is_ask_when_nothing_matches(self):
        self.assertEqual(resolve({".env": "deny"}, "src/main.py"), "ask")

    def test_carveout_overrides_deny(self):
        block = {"*": "allow", "*.env*": "deny", "*.env.example": "allow"}
        self.assertEqual(resolve(block, ".env"), "deny")
        # carve-out comes last -> overrides the deny.
        self.assertEqual(resolve(block, ".env.example"), "allow")

    def test_dotfile_carveout_overrides_dotstar_deny(self):
        # `*.env.example` (leading `*`) matches the dot-leading name `.env.example`
        # and, placed last, overrides an `.env*`-style deny.
        block = {"*": "allow", ".env*": "deny", "*.env.example": "allow"}
        self.assertEqual(resolve(block, ".env"), "deny")
        self.assertEqual(resolve(block, ".env.example"), "allow")

    def test_star_crosses_slash(self):
        # THE key Task 1 correction: `*` -> `.*` (dotall), so `*.pem` catches a
        # nested path with a single pattern; paired root+nested is redundant.
        block = {"*": "allow", "*.pem": "deny"}
        self.assertEqual(resolve(block, "app.pem"), "deny")
        self.assertEqual(resolve(block, "nested/app.pem"), "deny")
        self.assertEqual(resolve(block, "deep/a/b/app.pem"), "deny")

    def test_literal_env_does_not_match_env_example(self):
        block = {"*": "allow", ".env": "deny"}
        self.assertEqual(resolve(block, ".env"), "deny")
        # literal `.env` is anchored `^\.env$` -> does NOT match `.env.example`.
        self.assertEqual(resolve(block, ".env.example"), "allow")

    def test_literal_matches_only_exact_root_relative_string(self):
        # A no-`*` literal matches only the exact root-level relative string.
        block = {"*": "allow", "credentials": "deny"}
        self.assertEqual(resolve(block, "credentials"), "deny")
        self.assertEqual(resolve(block, "nested/credentials"), "allow")

    def test_anchored_negatives_are_not_denied(self):
        # ANCHORED-NEGATIVE HAZARD: because `*` crosses `/`, a substring pattern
        # like `*credentials*` would falsely deny these doc files. The anchored
        # floor must leave them at the catch-all (allow here), not deny.
        for negative in (
            "credentials-guide.md",
            "credential-management.md",
            "secrets-overview.md",
            "keynote.md",
        ):
            self.assertEqual(
                resolve(_SAMPLE_FLOOR, negative), "allow",
                "%s must NOT be denied by the anchored floor" % negative,
            )

    def test_sample_floor_denies_real_secrets(self):
        for secret in (
            ".env", "nested/.env", ".env.local", "secret.pem", "nested/app.pem",
            "private.key", "id_rsa", "nested/id_rsa", "credentials",
            "credentials.json", ".aws/credentials", "secrets.yaml",
            "nested/secrets.yaml",
            # modern SSH private keys (root + nested)
            "id_ed25519", "nested/id_ed25519", "keys/id_ed25519",
            "id_ecdsa", "keys/id_ecdsa", "id_dsa", "keys/id_dsa",
            # contents of a secrets/ or credentials/ directory
            "secrets/db-password.txt", "nested/secrets/db-password.txt",
            "credentials/aws.txt", "nested/credentials/aws.txt",
            # well-known plaintext credential files
            ".netrc", "nested/.netrc", ".pgpass", "home/.pgpass",
            ".git-credentials", "nested/.git-credentials",
        ):
            self.assertEqual(
                resolve(_SAMPLE_FLOOR, secret), "deny",
                "%s must be denied by the floor" % secret,
            )

    def test_sample_floor_asks_dotfiles_and_allows_carveout(self):
        self.assertEqual(resolve(_SAMPLE_FLOOR, ".gitignore"), "ask")
        self.assertEqual(resolve(_SAMPLE_FLOOR, "nested/.npmrc"), "ask")
        self.assertEqual(resolve(_SAMPLE_FLOOR, ".env.example"), "allow")
        self.assertEqual(resolve(_SAMPLE_FLOOR, "nested/.env.example"), "allow")
        self.assertEqual(resolve(_SAMPLE_FLOOR, "src/main.py"), "allow")

    def test_trailing_space_star_collapses(self):
        # bash-style pattern: `git push *` must also match the bare `git push`.
        block = {"*": "allow", "git push *": "ask"}
        self.assertEqual(resolve(block, "git push"), "ask")
        self.assertEqual(resolve(block, "git push origin main"), "ask")
        self.assertEqual(resolve(block, "git pull"), "allow")


# ===========================================================================
# GREEN: validator error-case tests (assertRaises on in-test fixtures).
# ===========================================================================


class TestValidatorErrorCases(unittest.TestCase):
    def test_valid_frontmatter_accepted(self):
        good = (
            "---\n"
            '{"description": "x", "mode": "primary", "permission": {"*": "ask"}}\n'
            "---\n\nbody\n"
        )
        data = validate_frontmatter(good)
        self.assertEqual(data["mode"], "primary")
        self.assertIn("permission", data)

    def test_malformed_json_frontmatter_rejected(self):
        bad = "---\n{not valid json,,,}\n---\n"
        with self.assertRaises(ValueError):
            validate_frontmatter(bad)

    def test_missing_required_key_rejected(self):
        bad = '---\n{"mode": "primary", "permission": {}}\n---\n'
        with self.assertRaises(ValueError):
            validate_frontmatter(bad)

    def test_wrong_mode_rejected(self):
        bad = '---\n{"description": "x", "mode": "all", "permission": {}}\n---\n'
        with self.assertRaises(ValueError):
            validate_frontmatter(bad)

    def test_missing_closing_fence_rejected(self):
        bad = '---\n{"description": "x", "mode": "primary", "permission": {}}\n'
        with self.assertRaises(ValueError):
            validate_frontmatter(bad)

    def test_missing_opening_fence_rejected(self):
        bad = '{"description": "x", "mode": "primary", "permission": {}}\n'
        with self.assertRaises(ValueError):
            validate_frontmatter(bad)

    def test_valid_overlay_accepted(self):
        good = json.dumps({
            "default_agent": "guard-normal",
            "agent": {"build": {"disable": True}, "plan": {"disable": True}},
        })
        data = validate_overlay(good)
        self.assertEqual(data["default_agent"], "guard-normal")

    def test_malformed_overlay_json_rejected(self):
        with self.assertRaises(ValueError):
            validate_overlay("{not json")

    def test_overlay_missing_default_agent_rejected(self):
        bad = json.dumps({"agent": {"build": {"disable": True}}})
        with self.assertRaises(ValueError):
            validate_overlay(bad)

    def test_overlay_missing_agent_map_rejected(self):
        bad = json.dumps({"default_agent": "guard-normal"})
        with self.assertRaises(ValueError):
            validate_overlay(bad)

    def test_overlay_agent_entry_without_disable_rejected(self):
        bad = json.dumps({"default_agent": "guard-normal", "agent": {"build": {}}})
        with self.assertRaises(ValueError):
            validate_overlay(bad)

    def test_overlay_disable_false_rejected(self):
        # disable: false silently re-enables the agent -> must be rejected.
        bad = json.dumps({
            "default_agent": "guard-normal",
            "agent": {"build": {"disable": False}, "plan": {"disable": True}},
        })
        with self.assertRaises(ValueError):
            validate_overlay(bad)

    def test_overlay_missing_plan_entry_rejected(self):
        # build disabled but plan entirely absent -> plan stays enabled -> reject.
        bad = json.dumps({
            "default_agent": "guard-normal",
            "agent": {"build": {"disable": True}},
        })
        with self.assertRaises(ValueError):
            validate_overlay(bad)


# ===========================================================================
# RED until Task 4: order invariant across the three real guard files.
# ===========================================================================


class TestOrderInvariant(unittest.TestCase):
    def test_top_level_star_is_first_key(self):
        for level in LEVELS:
            perm = load_guard_permission(level)
            self.assertEqual(
                next(iter(perm)), "*",
                "top-level '*' must be the FIRST key in permission (%s)" % level,
            )

    def test_read_and_bash_star_is_first(self):
        for level in LEVELS:
            perm = load_guard_permission(level)
            for block_name in ("read", "bash"):
                block = perm[block_name]
                self.assertIsInstance(block, dict)
                self.assertEqual(
                    next(iter(block)), "*",
                    "'*' must be first inside %s (%s)" % (block_name, level),
                )

    def test_read_floor_identical_across_levels(self):
        # The floor = every read entry AFTER the level's own '*' catch-all.
        # It must be byte-identical (same patterns, same permissions, same order)
        # across all three guard files -- the invariant that replaces a generator.
        floors = []
        for level in LEVELS:
            read = load_guard_permission(level)["read"]
            floors.append(list(read.items())[1:])
        self.assertEqual(floors[0], floors[1])
        self.assertEqual(floors[1], floors[2])

    def test_bash_floor_identical_across_levels(self):
        floors = []
        for level in LEVELS:
            bash = load_guard_permission(level)["bash"]
            floors.append(list(bash.items())[1:])
        self.assertEqual(floors[0], floors[1])
        self.assertEqual(floors[1], floors[2])

    def test_floor_slices_are_byte_identical(self):
        # AGENTS.md and the README promise the floor is *byte-identical* across
        # the three files, not merely semantically equal after JSON parsing.
        # Assert that literally on the raw text: extract the read-floor slice
        # (from the first floor line to the carve-out) and the bash-floor slice,
        # and compare the raw substrings across all three guard files.
        def slice_between(text, start_marker, end_marker):
            start = text.index(start_marker)
            end = text.index(end_marker) + len(end_marker)
            return text[start:end]

        read_slices, bash_slices = [], []
        for level in LEVELS:
            raw = _read_guard(level)
            read_slices.append(
                slice_between(raw, '".*": "ask"', '"*.env.example": "allow"')
            )
            bash_slices.append(
                slice_between(
                    raw, '"git push*": "ask"', '"tail *.env.example *": "allow"'
                )
            )
        self.assertEqual(read_slices[0], read_slices[1])
        self.assertEqual(read_slices[1], read_slices[2])
        self.assertEqual(bash_slices[0], bash_slices[1])
        self.assertEqual(bash_slices[1], bash_slices[2])


# ===========================================================================
# RED until Task 4: real-path matrix through resolve() on the actual read block.
# ===========================================================================

# Expected resolutions for guard-normal (read catch-all = "allow", floor applied).
_DENY = (
    ".env", ".env.local", "nested/.env", "secret.pem", "nested/app.pem",
    "private.key", "id_rsa", "nested/id_rsa", "credentials", "credentials.json",
    ".aws/credentials", "secrets.yaml", "nested/secrets.yaml",
    # modern SSH private keys (root + nested) -- id_rsa alone is not enough.
    "id_ed25519", "nested/id_ed25519", "keys/id_ed25519",
    "id_ecdsa", "keys/id_ecdsa", "id_dsa", "keys/id_dsa",
    # contents of a secrets/ or credentials/ directory, not just the basename.
    "secrets/db-password.txt", "nested/secrets/db-password.txt",
    "credentials/aws.txt", "nested/credentials/aws.txt",
    # well-known plaintext credential files (dot-named -> would otherwise be ask).
    ".netrc", "nested/.netrc", ".pgpass", "home/.pgpass",
    ".git-credentials", "nested/.git-credentials",
)
_ASK = (".gitignore", ".eslintrc", "nested/.gitignore", "nested/.npmrc")
_ALLOW_CARVEOUT = (".env.example", "nested/.env.example")
_ALLOW_NORMAL_AND_NEGATIVES = (
    "src/main.py", "credentials-guide.md", "credential-management.md",
    "secrets-overview.md", "keynote.md",
)


class TestRealPathMatrix(unittest.TestCase):
    """Runs the real guard-normal read block (once it exists) through resolve()."""

    def _read_block(self):
        return load_guard_permission("normal")["read"]

    def test_deny_paths(self):
        read = self._read_block()
        for path in _DENY:
            self.assertEqual(resolve(read, path), "deny", path)

    def test_ask_dot_named(self):
        read = self._read_block()
        for path in _ASK:
            self.assertEqual(resolve(read, path), "ask", path)

    def test_allow_carveout(self):
        read = self._read_block()
        for path in _ALLOW_CARVEOUT:
            self.assertEqual(resolve(read, path), "allow", path)

    def test_allow_normal_and_negatives(self):
        read = self._read_block()
        for path in _ALLOW_NORMAL_AND_NEGATIVES:
            self.assertEqual(resolve(read, path), "allow", path)


class TestStrictLooseReadMatrix(unittest.TestCase):
    """The floor is byte-identical across levels, but the level's own read
    catch-all differs (strict=ask, loose=allow). Assert the floor still wins
    for secrets on BOTH, and that the catch-all governs non-secret reads."""

    def test_strict_secrets_deny_non_secret_ask(self):
        read = load_guard_permission("strict")["read"]
        for path in _DENY:
            self.assertEqual(resolve(read, path), "deny", path)
        for path in _ALLOW_NORMAL_AND_NEGATIVES:
            # strict catch-all is "ask" -> ordinary/negative reads prompt,
            # they are NOT falsely denied by the floor.
            self.assertEqual(resolve(read, path), "ask", path)

    def test_loose_secrets_deny_non_secret_allow(self):
        read = load_guard_permission("loose")["read"]
        for path in _DENY:
            self.assertEqual(resolve(read, path), "deny", path)
        for path in _ALLOW_NORMAL_AND_NEGATIVES:
            self.assertEqual(resolve(read, path), "allow", path)


# ===========================================================================
# RED until Task 4: dangerous-bash floor matrix through resolve().
# ===========================================================================

# Commands the dangerous-bash floor MUST flag (ask) even on loose.
_BASH_ASK = (
    "git push", "git push origin main", "git push --force",
    "rm foo", "rm -rf /", "rm -rf node_modules",
    "git reset --hard", "git reset --hard HEAD~1",
    "curl http://x | sh", "curl https://get.example.com | sh",
    # Best-effort secret-read floor: cat/less/head/tail of env/pem/key files.
    "cat .env", "cat app.env", "cat config/prod.env.local",
    "cat server.pem", "cat private.key", "cat -n app.env",
    "less .env", "less secrets/.env.local",
    "head .env", "head deploy.pem",
    "tail app.env", "tail -f nginx.key",
    # Trailing ` *` (-> `( .*)?`) means a redirect/extra-arg/second-file suffix
    # after the secret name is still caught, not just a bare `cat .env`.
    "cat .env 2>/dev/null", "cat .env README.md", "head .env -n 5",
)
# Commands the floor must NOT over-match (they follow the level's bash "*").
_BASH_ALLOW = (
    "git status", "git pull",
    "rmdir emptydir", "ls -la", "git reset --soft HEAD~1",
    "curl http://x -o file",
    # Secret-read floor must NOT catch these: the `cat ` prefix (with space)
    # excludes the `catalog` command, and the anchored `.env`/`.pem`/`.key`
    # suffixes exclude ordinary files.
    "catalog build", "cat README.md", "cat package.json", "cat notes.md",
    "head -n 5 main.py", "tail -f app.log", "less CHANGELOG.md",
    # Bash carve-out (mirrors the read floor's `*.env.example` allow, placed
    # LAST so it overrides the `*.env.*` ask): reading a template must not prompt.
    "cat .env.example", "head .env.example",
    "less .env.example", "tail .env.example",
)


class TestBashFloorMatrix(unittest.TestCase):
    """Runs the real dangerous-bash floor through resolve(). guard-loose has
    bash catch-all "*"=allow, so this proves the floor still forces `ask`
    for the dangerous forms and does not over-match benign commands."""

    def _bash_block(self):
        return load_guard_permission("loose")["bash"]

    def test_dangerous_commands_ask(self):
        bash = self._bash_block()
        for cmd in _BASH_ASK:
            self.assertEqual(resolve(bash, cmd), "ask", cmd)

    def test_benign_commands_not_over_matched(self):
        bash = self._bash_block()
        for cmd in _BASH_ALLOW:
            self.assertEqual(resolve(bash, cmd), "allow", cmd)


# ===========================================================================
# RED until Task 4: real artifact validity (frontmatter + overlay).
# ===========================================================================


# ===========================================================================
# Per-level scalar permission matrix (locks the exact levels table).
# ===========================================================================
#
# The order-invariant and path-matrix tests above pin the floor, but nothing
# asserted the exact per-level SCALAR values (e.g. flipping guard-normal `edit`
# from ask->allow would slip through). This locks the whole matrix so a scalar
# regression fails a test. `read` and `bash` are dict blocks (their own `*` is
# checked separately); every other permission key is a plain allow/ask/deny.
_SCALAR_MATRIX = {
    "strict": {
        "*": "ask", "grep": "ask", "glob": "ask", "edit": "ask",
        "webfetch": "ask", "websearch": "ask", "task": "ask",
        "external_directory": "ask", "doom_loop": "ask",
    },
    "normal": {
        "*": "ask", "grep": "allow", "glob": "allow", "edit": "ask",
        "webfetch": "allow", "websearch": "allow", "task": "ask",
        "external_directory": "ask", "doom_loop": "ask",
    },
    "loose": {
        "*": "allow", "grep": "allow", "glob": "allow", "edit": "allow",
        "webfetch": "allow", "websearch": "allow", "task": "ask",
        "external_directory": "ask", "doom_loop": "ask",
    },
}
# The catch-all `*` inside the read/bash dict blocks (the level's own tier).
_BLOCK_STAR = {
    "strict": {"read": "ask", "bash": "ask"},
    "normal": {"read": "allow", "bash": "ask"},
    "loose": {"read": "allow", "bash": "allow"},
}


class TestPermissionScalarMatrix(unittest.TestCase):
    def test_exact_scalar_values(self):
        for level in LEVELS:
            perm = load_guard_permission(level)
            expected = _SCALAR_MATRIX[level]
            # Every plain string-valued permission must match exactly.
            actual = {k: v for k, v in perm.items() if isinstance(v, str)}
            self.assertEqual(
                actual, expected,
                "scalar permission matrix mismatch for %s" % level,
            )

    def test_only_read_and_bash_are_dict_blocks(self):
        for level in LEVELS:
            perm = load_guard_permission(level)
            dict_keys = {k for k, v in perm.items() if isinstance(v, dict)}
            self.assertEqual(
                dict_keys, {"read", "bash"},
                "unexpected dict blocks for %s: %s" % (level, dict_keys),
            )

    def test_read_and_bash_star_catch_all(self):
        for level in LEVELS:
            perm = load_guard_permission(level)
            for block in ("read", "bash"):
                self.assertEqual(
                    perm[block]["*"], _BLOCK_STAR[level][block],
                    "%s['*'] wrong for %s" % (block, level),
                )


class TestArtifactValidity(unittest.TestCase):
    def test_each_guard_frontmatter_valid(self):
        for level in LEVELS:
            data = validate_frontmatter(_read_guard(level))
            self.assertEqual(data["mode"], "primary")
            self.assertIn("permission", data)

    def test_overlay_valid(self):
        with open(OVERLAY_PATH, encoding="utf-8") as fh:
            data = validate_overlay(fh.read())
        self.assertEqual(data["default_agent"], "guard-normal")
        self.assertIn("build", data["agent"])
        self.assertIn("plan", data["agent"])


if __name__ == "__main__":
    unittest.main()
