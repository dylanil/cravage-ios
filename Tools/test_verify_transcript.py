"""Tools/verify_transcript.py, run as a person would run it, must pass only a complete
cravage-transcript-2 file. The pinned verify_round.py picks its checks from the file's own format
field, so a genuine iPhone transcript relabelled as another format, with its agreement signatures
removed and its sum recomputed without the modulus, still passed there."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import verify_round  # noqa: E402

FIXTURE = os.path.join(ROOT, "CravageCore/Tests/CravageCoreTests/Fixtures/core_vectors.json")
CLI = os.path.join(HERE, "verify_transcript.py")


def golden():
    with open(FIXTURE, encoding="utf-8") as f:
        return json.load(f)["golden"]["transcript"]


def downgraded(fmt):
    """The golden file with its v2-only signatures removed and the sum and average recomputed the
    ordinary way, every share signature intact. fmt None removes the format field."""
    t = dict(golden())
    del t["confirms"], t["roomcode_confirms"]
    if fmt is None:
        del t["format"]
    else:
        t["format"] = fmt
    total = sum(int(t["shares"][p]) for p in t["parties"])
    t["sum"] = str(total)
    t["average"] = verify_round.format_average_fixed(total, len(t["parties"]))
    return t


class StrictTranscriptCheck(unittest.TestCase):
    def run_cli(self, content):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "t.json")
            with open(path, "w", encoding="utf-8") as f:
                f.write(content if isinstance(content, str) else json.dumps(content))
            return subprocess.run([sys.executable, CLI, path], capture_output=True, text=True)

    def test_genuine_iphone_transcript_passes(self):
        r = self.run_cli(golden())
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("PASS", r.stdout)

    def test_downgraded_format_is_refused(self):
        for fmt in ("cravage-transcript-1", "something-else", None):
            with self.subTest(format=fmt):
                t = downgraded(fmt)
                # The premise: the pinned web verifier accepts this file.
                self.assertEqual(verify_round.check_transcript(t), [])
                r = self.run_cli(t)
                self.assertNotEqual(r.returncode, 0, r.stdout)
                self.assertNotIn("PASS", r.stdout)

    def test_missing_agreement_signatures_are_refused(self):
        for name in ("confirms", "roomcode_confirms"):
            with self.subTest(missing=name):
                t = golden()
                del t[name]
                self.assertNotEqual(self.run_cli(t).returncode, 0)

    def test_changed_average_or_label_is_refused(self):
        for key, value in (("average", "21"), ("label", "Something else")):
            with self.subTest(changed=key):
                t = golden()
                t[key] = value
                self.assertNotEqual(self.run_cli(t).returncode, 0)

    def test_not_a_transcript_is_refused(self):
        for content in ("[]", "not json", '"text"'):
            with self.subTest(content=content):
                r = self.run_cli(content)
                self.assertNotEqual(r.returncode, 0)
                self.assertNotIn("Traceback", r.stderr)


if __name__ == "__main__":
    unittest.main()
