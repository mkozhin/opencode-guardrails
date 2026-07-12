"""Verify that every local link/path referenced in the READMEs exists.

Parses ``README.md`` and ``README_RU.md`` for markdown links ``[text](target)``
where the target is a local file or relative path, and asserts each referenced
path exists in the repository. External ``http(s)://`` URLs and in-page anchors
(``#section``) are ignored (no network access, no filesystem check).

Includes a negative test proving the checker actually reports breakage rather
than silently passing.
"""

import os
import re
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Markdown inline link: [text](target)
_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def extract_local_targets(markdown_text):
    """Return the list of local link targets found in *markdown_text*.

    A target is "local" when it is not an external URL and not a pure in-page
    anchor. Any ``#fragment`` and ``?query`` suffix is stripped before the path
    is returned, so ``docs/x.md#section`` yields ``docs/x.md``.
    """
    targets = []
    for raw in _LINK_RE.findall(markdown_text):
        target = raw.strip()
        # Skip external URLs and protocol-relative / mail links.
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", target):
            continue
        if target.startswith("mailto:"):
            continue
        # Skip pure in-page anchors.
        if target.startswith("#"):
            continue
        # Strip any anchor / query suffix from the path.
        path = target.split("#", 1)[0].split("?", 1)[0]
        if not path:
            continue
        targets.append(path)
    return targets


def find_broken_links(markdown_text, base_dir):
    """Return targets from *markdown_text* that do not resolve under *base_dir*.

    Never raises for a missing path — a broken link is reported by inclusion in
    the returned list, so callers (and tests) can assert on it without the
    checker itself crashing.
    """
    broken = []
    for path in extract_local_targets(markdown_text):
        resolved = os.path.normpath(os.path.join(base_dir, path))
        if not os.path.exists(resolved):
            broken.append(path)
    return broken


class ReadmeLinksTest(unittest.TestCase):
    READMES = ("README.md", "README_RU.md")

    def _read(self, name):
        with open(os.path.join(REPO_ROOT, name), encoding="utf-8") as fh:
            return fh.read()

    def test_readmes_exist(self):
        for name in self.READMES:
            self.assertTrue(
                os.path.isfile(os.path.join(REPO_ROOT, name)),
                "missing README file: %s" % name,
            )

    def test_no_broken_local_links(self):
        for name in self.READMES:
            text = self._read(name)
            broken = find_broken_links(text, REPO_ROOT)
            self.assertEqual(
                broken, [], "%s has broken local links: %s" % (name, broken)
            )

    def test_mutual_cross_link_present(self):
        # README.md must link to README_RU.md and vice versa.
        en = self._read("README.md")
        ru = self._read("README_RU.md")
        self.assertIn("README_RU.md", extract_local_targets(en))
        self.assertIn("README.md", extract_local_targets(ru))

    def test_checker_detects_broken_link(self):
        # Negative case: a fixture with a broken local link must be reported,
        # and the checker itself must not crash.
        fixture = (
            "See [good](README.md) and [bad](docs/does-not-exist.md).\n"
            "External [site](https://example.com) and [anchor](#top) are ignored."
        )
        broken = find_broken_links(fixture, REPO_ROOT)
        self.assertIn("docs/does-not-exist.md", broken)
        self.assertNotIn("README.md", broken)
        self.assertNotIn("https://example.com", broken)

    def test_checker_ignores_external_and_anchors(self):
        fixture = "[a](https://x.example) [b](#section) [c](mailto:x@y.z)"
        self.assertEqual(extract_local_targets(fixture), [])


if __name__ == "__main__":
    unittest.main()
