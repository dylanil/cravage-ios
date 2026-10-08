"""Tools/check_honesty_copy.sh, run against a throwaway folder laid out like this repository.

Its comment filter once dropped every line containing "://", so a forbidden claim next to a web
address passed. Public pages (README, privacy policy, support, home page) are checked too."""
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check_honesty_copy.sh")
CLAIM = "Your figure is safe to share"


class HonestyCopyLint(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)
        os.makedirs(os.path.join(self.root, "Tools"))
        os.makedirs(os.path.join(self.root, "Cravage/Resources"))
        os.makedirs(os.path.join(self.root, "docs"))
        shutil.copy(SCRIPT, os.path.join(self.root, "Tools"))
        self.write("Cravage/Resources/Info.plist", "<plist></plist>\n")
        self.write("Cravage/View.swift", 'let s = "Hello"\n')
        for name in ("project.yml", "README.md", "docs/index.md", "docs/privacy-policy.md",
                     "docs/support.md"):
            self.write(name, "Plain text\n")
        self.write("docs/APP_STORE.md", "## Listing copy\n\nPlain text\n\n## Notes\n\nnothing saved\n")

    def write(self, name, text):
        with open(os.path.join(self.root, name), "w", encoding="utf-8") as f:
            f.write(text)

    def run_lint(self):
        return subprocess.run(["bash", os.path.join(self.root, "Tools/check_honesty_copy.sh")],
                              capture_output=True, text=True)

    def test_clean_tree_passes(self):
        r = self.run_lint()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_claim_in_a_string_fails(self):
        self.write("Cravage/View.swift", 'let s = "' + CLAIM + '"\n')
        self.assertNotEqual(self.run_lint().returncode, 0)

    def test_claim_next_to_a_web_address_fails(self):
        self.write("Cravage/View.swift", 'let s = "' + CLAIM + ', see https://example.com"\n')
        self.assertNotEqual(self.run_lint().returncode, 0)

    def test_claim_in_a_code_comment_passes(self):
        self.write("Cravage/View.swift", "    // " + CLAIM + "\n    /// " + CLAIM + "\n")
        r = self.run_lint()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_claim_on_a_public_page_fails(self):
        for name in ("README.md", "docs/index.md", "docs/privacy-policy.md", "docs/support.md"):
            with self.subTest(page=name):
                self.write(name, CLAIM + " (https://example.com)\n")
                self.assertNotEqual(self.run_lint().returncode, 0)
                self.write(name, "Plain text\n")


if __name__ == "__main__":
    unittest.main()
