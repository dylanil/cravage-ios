"""Exercise the mutation CLI with a controlled external Swift command."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class MutationGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "Tools").mkdir()
        (self.root / "CravageCore").mkdir()
        shutil.copyfile(Path(__file__).with_name("check_mutations.py"), self.root / "Tools/check_mutations.py")
        self.source = self.root / "CravageCore/Guard.swift"
        self.source.write_text("guard intact\n")
        (self.root / "Tools/mutations.json").write_text(json.dumps({"mutations": [{
            "name": "example guard", "file": "CravageCore/Guard.swift",
            "find": "guard intact", "replace": "guard removed",
        }]}))
        (self.root / "bin").mkdir()
        swift = self.root / "bin/swift"
        swift.write_text(f"#!{sys.executable}\n" + '''
import os
from pathlib import Path
import sys
import time
mutated = "removed" in Path("CravageCore/Guard.swift").read_text()
mode = os.environ.get("MUTATION_TEST_MODE", "compile")
if mutated and mode == "compile":
    print("error: controlled compiler failure")
    sys.exit(1)
if sys.argv[1] == "build":
    sys.exit(0)
if mode == "baseline":
    print("error: baseline could not launch")
    sys.exit(1)
if mutated and mode == "assertion":
    print("Test Case 'Example.testGuard' failed (0.001 seconds).")
    sys.exit(1)
if mutated and mode == "infrastructure":
    print("error: test process could not launch")
    sys.exit(1)
if mutated and mode == "empty":
    sys.exit(0)
if mutated and mode == "hang":
    print("Test Case 'Example.testGuard' failed (0.001 seconds).", flush=True)
    time.sleep(30)
if mutated and mode == "silenthang":
    time.sleep(30)
if mutated and mode == "isolation":
    if "removed" in Path(os.environ["MUTATION_ORIGINAL_SOURCE"]).read_text():
        print("error: working source was mutated")
        sys.exit(1)
    print("Test Case 'Example.testGuard' failed (0.001 seconds).")
    sys.exit(1)
print("Test Case 'Example.testGuard' passed (0.001 seconds).")
print("Executed 1 test, with 0 failures (0 unexpected)")
''')
        swift.chmod(0o755)

    def run_gate(self, mode="compile", args=()):
        env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                   MUTATION_TEST_MODE=mode, MUTATION_ORIGINAL_SOURCE=str(self.source))
        return subprocess.run([sys.executable, "Tools/check_mutations.py", *args], cwd=self.root,
                              env=env, capture_output=True, text=True)

    def test_compile_failure_is_not_a_caught_mutation(self):
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("caught: example guard", result.stdout)
        self.assertEqual(self.source.read_text(), "guard intact\n")

    def test_assertion_failure_is_caught_and_evidence_is_retained(self):
        result = self.run_gate("assertion")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("caught: example guard: Example.testGuard", result.stdout)
        logs = list((self.root / ".build/mutations").glob("*/mutation-1-test.log"))
        self.assertEqual(len(logs), 1)
        self.assertIn("Example.testGuard", logs[0].read_text())

    def test_runner_that_hangs_after_a_failing_test_still_counts_as_caught(self):
        result = self.run_gate("hang", args=("--timeout", "3"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("caught: example guard", result.stdout)
        self.assertIn("runner hung after reporting", result.stdout)

    def test_runner_that_hangs_with_no_failing_test_is_not_caught(self):
        result = self.run_gate("silenthang", args=("--timeout", "3"))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ERROR: example guard", result.stdout)
        self.assertIn("runner hung with no failing test", result.stdout)

    def test_passing_mutation_is_reported_as_surviving(self):
        result = self.run_gate("pass")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SURVIVED: example guard", result.stdout)

    def test_infrastructure_failure_is_not_caught(self):
        result = self.run_gate("infrastructure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR: example guard", result.stdout)

    def test_zero_tests_is_an_error(self):
        result = self.run_gate("empty")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR: example guard", result.stdout)

    def test_unknown_suite_cannot_silently_skip_a_guard(self):
        path = self.root / "Tools/mutations.json"
        manifest = json.loads(path.read_text())
        manifest["mutations"][0]["suite"] = "typo"
        path.write_text(json.dumps(manifest))
        result = self.run_gate("assertion")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown mutation suite", result.stderr)

    def test_failing_baseline_stops_before_mutation(self):
        result = self.run_gate("baseline")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unmutated suite does not pass", result.stdout)
        self.assertNotIn("caught:", result.stdout)
        self.assertEqual(list((self.root / ".build/mutations").glob("*/mutation-*-build.log")), [])

    def test_mutation_never_changes_the_shared_checkout(self):
        result = self.run_gate("isolation")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.source.read_text(), "guard intact\n")

    def test_app_mutations_build_then_require_a_real_simulator_test_failure(self):
        for directory in ["Cravage", "CravageTests", "Cravage.xcodeproj", "Config"]:
            (self.root / directory).mkdir()
        self.source = self.root / "Cravage/Guard.swift"
        self.source.write_text("guard intact\n")
        (self.root / "Config/Local.xcconfig").write_text("LOCAL_SIGNING_SETTINGS\n")
        (self.root / "Tools/mutations.json").write_text(json.dumps({"mutations": [{
            "name": "app guard", "suite": "app", "file": "Cravage/Guard.swift",
            "find": "guard intact", "replace": "guard removed",
        }]}))
        xcode = self.root / "bin/xcodebuild"
        xcode.write_text(f"#!{sys.executable}\n" + '''
import os
from pathlib import Path
import sys
assert not Path("Config/Local.xcconfig").exists(), "private signing config copied"
assert "CODE_SIGNING_ALLOWED=NO" in sys.argv
assert sys.argv[sys.argv.index("-destination") + 1] == "platform=iOS Simulator,name=Test Phone"
mutated = "removed" in Path("Cravage/Guard.swift").read_text()
assert "removed" not in Path(os.environ["MUTATION_ORIGINAL_SOURCE"]).read_text()
if sys.argv[1] == "build-for-testing":
    if mutated and os.environ["MUTATION_TEST_MODE"] == "compile":
        print("error: controlled compiler failure")
        sys.exit(1)
    Path("built").touch()
    sys.exit(0)
assert sys.argv[1] == "test-without-building"
assert Path("built").exists(), "tests ran before compilation"
if mutated:
    print("Test Case 'App.testGuard' failed (0.001 seconds).")
    sys.exit(1)
print("Test Case 'App.testGuard' passed (0.001 seconds).")
''')
        xcode.chmod(0o755)
        args = ("--suite", "app", "--destination", "platform=iOS Simulator,name=Test Phone")
        compiled = self.run_gate("assertion", args)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        self.assertIn("caught: app guard: App.testGuard", compiled.stdout)
        broken = self.run_gate("compile", args)
        self.assertNotEqual(broken.returncode, 0)
        self.assertIn("ERROR: app guard", broken.stdout)
        self.assertNotIn("caught:", broken.stdout)


if __name__ == "__main__":
    unittest.main()
