import importlib.util
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "validate-change.py"
spec = importlib.util.spec_from_file_location("validate_change", SCRIPT)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ReceiptLifecycleTests(unittest.TestCase):
    def setUp(self):
        scratch = SCRIPT.parent.parent / ".harness" / "test-tmp"
        remove_scratch = not scratch.exists()
        scratch.mkdir(parents=True, exist_ok=True)
        if remove_scratch:
            self.addCleanup(scratch.rmdir)
        self.root = scratch / f"receipt-{os.getpid()}-{time.time_ns()}"
        self.root.mkdir()
        self.addCleanup(shutil.rmtree, self.root, True)

    def test_receipt_replacement_is_atomic_and_cleans_a_failed_temporary_write(self):
        receipt = self.root / "receipt.json"
        receipt.write_text(json.dumps({"status": "previous"}) + "\n")

        with mock.patch.object(runner.os, "replace", side_effect=OSError("replacement refused")):
            with self.assertRaisesRegex(OSError, "replacement refused"):
                runner.write_json_atomic(receipt, {"status": "cancelled"})

        self.assertEqual(json.loads(receipt.read_text()), {"status": "previous"})
        self.assertEqual(list(self.root.glob("*.tmp")), [])
        runner.write_json_atomic(receipt, {"status": "cancelled"})
        self.assertEqual(json.loads(receipt.read_text()), {"status": "cancelled"})

    def test_run_lifecycle_records_the_first_termination_signal(self):
        handlers = {}

        def install(signum, handler):
            handlers[signum] = handler

        with mock.patch.object(runner.signal, "getsignal", return_value=signal.SIG_DFL), \
             mock.patch.object(runner.signal, "signal", side_effect=install):
            with runner.RunLifecycle() as lifecycle:
                with self.assertRaises(KeyboardInterrupt):
                    handlers[signal.SIGTERM](signal.SIGTERM, None)
                handlers[signal.SIGINT](signal.SIGINT, None)

        self.assertEqual(lifecycle.signum, signal.SIGTERM)

    def test_interrupt_during_spawn_registers_and_cleans_the_child(self):
        plan = {
            "checks": [
                {"name": "active", "argv": ["fixture"], "timeout_seconds": 30},
                {"name": "pending", "argv": ["fixture"], "timeout_seconds": 30},
            ]
        }
        process = mock.Mock(pid=1234, returncode=-9)
        lifecycle = runner.RunLifecycle()

        def interrupt_after_spawn(*_args, **_kwargs):
            lifecycle._interrupt(signal.SIGTERM, None)
            return process

        with mock.patch.object(runner.subprocess, "Popen", side_effect=interrupt_after_spawn), \
             mock.patch.object(runner, "stop_group", return_value=None) as stop_group:
            results = runner.run_checks(plan, self.root, self.root, 1, lifecycle=lifecycle)

        self.assertEqual(lifecycle.signum, signal.SIGTERM)
        self.assertEqual([result["status"] for result in results], ["cancelled", "not_run"])
        self.assertEqual(results[0]["exit_code"], -9)
        self.assertEqual(results[0]["log_sha256"], runner.file_sha256(self.root / "active.log"))
        stop_group.assert_called_once_with(process)

    def test_interrupt_during_tool_fingerprint_spawn_cleans_the_child(self):
        process = mock.Mock(pid=1234, returncode=-9)
        lifecycle = runner.RunLifecycle()

        def interrupt_after_spawn(*_args, **_kwargs):
            lifecycle._interrupt(signal.SIGTERM, None)
            return process

        with mock.patch.object(runner.subprocess, "Popen", side_effect=interrupt_after_spawn), \
             mock.patch.object(runner, "stop_group", return_value=None) as stop_group:
            with self.assertRaises(KeyboardInterrupt):
                runner.tool_fingerprint(["fixture", "--version"], self.root, lifecycle)

        self.assertEqual(lifecycle.signum, signal.SIGTERM)
        process.communicate.assert_not_called()
        stop_group.assert_called_once_with(process)

    def test_interrupt_during_tool_fingerprint_cleanup_finishes_cleanup(self):
        process = mock.Mock(pid=1234, returncode=0)
        process.communicate.return_value = (b"version", b"")
        lifecycle = runner.RunLifecycle()
        cleanup_finished = False

        def interrupt_during_cleanup(_process):
            nonlocal cleanup_finished
            lifecycle._interrupt(signal.SIGTERM, None)
            cleanup_finished = True

        with mock.patch.object(runner.subprocess, "Popen", return_value=process), \
             mock.patch.object(runner, "stop_group", side_effect=interrupt_during_cleanup):
            with self.assertRaises(KeyboardInterrupt):
                runner.tool_fingerprint(["fixture", "--version"], self.root, lifecycle)

        self.assertTrue(cleanup_finished)
        self.assertEqual(lifecycle.signum, signal.SIGTERM)
        process.communicate.assert_called_once_with(timeout=30)

    def test_interrupt_before_tool_fingerprint_cleanup_guard_retries_cleanup(self):
        process = mock.Mock(pid=1234, returncode=0)
        process.communicate.return_value = (b"version", b"")
        lifecycle = runner.RunLifecycle()
        defer_interrupts = lifecycle.defer_interrupts
        defer_calls = 0

        def interrupt_before_cleanup_guard():
            nonlocal defer_calls
            defer_calls += 1
            if defer_calls == 2:
                lifecycle._interrupt(signal.SIGTERM, None)
            return defer_interrupts()

        with mock.patch.object(runner.subprocess, "Popen", return_value=process), \
             mock.patch.object(lifecycle, "defer_interrupts", side_effect=interrupt_before_cleanup_guard), \
             mock.patch.object(runner, "stop_group", return_value=None) as stop_group:
            with self.assertRaises(KeyboardInterrupt):
                runner.tool_fingerprint(["fixture", "--version"], self.root, lifecycle)

        self.assertEqual(defer_calls, 3)
        self.assertEqual(lifecycle.signum, signal.SIGTERM)
        process.communicate.assert_called_once_with(timeout=30)
        stop_group.assert_called_once_with(process)

    def test_tool_fingerprint_preserves_callers_without_a_lifecycle(self):
        process = mock.Mock(pid=1234, returncode=0)
        process.communicate.return_value = (b"version", b"details")

        with mock.patch.object(runner.subprocess, "Popen", return_value=process), \
             mock.patch.object(runner, "stop_group", return_value=None) as stop_group:
            fingerprint = runner.tool_fingerprint(["fixture", "--version"], self.root)

        self.assertEqual(fingerprint, runner.hashlib.sha256(b"version\0details").hexdigest())
        process.communicate.assert_called_once_with(timeout=30)
        stop_group.assert_called_once_with(process)

    def test_receipt_finalization_recovers_from_interrupt_before_first_write(self):
        path = self.root / "receipt.json"
        plan = {"checks": [{"name": "pending", "argv": ["fixture"], "timeout_seconds": 30}]}
        receipt = {"schema": 2, "checks": []}
        lifecycle = runner.RunLifecycle()
        write_json_atomic = runner.write_json_atomic
        calls = 0

        def interrupt_once(receipt_path, value):
            nonlocal calls
            calls += 1
            if calls == 1:
                lifecycle._interrupt(signal.SIGTERM, None)
            write_json_atomic(receipt_path, value)

        with mock.patch.object(runner, "write_json_atomic", side_effect=interrupt_once):
            runner.finalize_receipt(path, receipt, plan, lifecycle, time.monotonic())

        saved = json.loads(path.read_text())
        self.assertEqual(calls, 2)
        self.assertEqual(saved["status"], "cancelled")
        self.assertEqual(saved["signal"], "SIGTERM")
        self.assertEqual(saved["checks"][0]["status"], "not_run")
        self.assertIn("finished_at", saved)
        self.assertEqual(list(self.root.glob("*.tmp")), [])

    def test_receipt_finalization_defers_interrupt_through_atomic_cleanup(self):
        path = self.root / "receipt.json"
        plan = {"checks": [{"name": "pending", "argv": ["fixture"], "timeout_seconds": 30}]}
        receipt = {"schema": 2, "checks": []}
        lifecycle = runner.RunLifecycle()
        replace = runner.os.replace
        calls = 0

        def interrupt_after_replace(source, destination):
            nonlocal calls
            calls += 1
            replace(source, destination)
            if calls == 1:
                lifecycle._interrupt(signal.SIGTERM, None)

        with mock.patch.object(runner.os, "replace", side_effect=interrupt_after_replace):
            runner.finalize_receipt(path, receipt, plan, lifecycle, time.monotonic())

        saved = json.loads(path.read_text())
        self.assertEqual(calls, 2)
        self.assertEqual(saved["status"], "cancelled")
        self.assertEqual(saved["signal"], "SIGTERM")
        self.assertEqual(saved["checks"][0]["status"], "not_run")
        self.assertEqual(list(self.root.glob("*.tmp")), [])


@unittest.skipUnless(os.name == "posix", "process groups require POSIX")
class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / ".harness").mkdir()
        (self.root / ".gitignore").write_text(".harness/\n")
        (self.root / "source.txt").write_text("original\n")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.STDOUT)

    def check(self, name, code, timeout=3):
        return {"name": name, "argv": [sys.executable, "-c", code], "timeout_seconds": timeout}

    def run_plan(self, checks, minimum=0, reuse=None, env=None):
        plan = self.root / ".harness" / "plan.json"
        plan.write_text(json.dumps({"reason": "Validation runner integration fixtures", "minimum_free_gib": minimum, "checks": checks}))
        command = [sys.executable, str(SCRIPT), str(plan)]
        if reuse:
            command.extend(["--reuse", str(reuse)])
        result = subprocess.run(command, cwd=self.root, capture_output=True, text=True, timeout=15, env=env)
        paths = sorted((self.root / ".harness" / "validation").glob("*/receipt.json"))
        self.assertTrue(paths, result.stderr + result.stdout)
        self.last_receipt = paths[-1]
        return result, json.loads(paths[-1].read_text())

    def counted_check(self, name="counted"):
        check = self.check(name, "from pathlib import Path; p=Path('.harness/count'); p.write_text(str(int(p.read_text())+1) if p.exists() else '1'); print('checked')")
        check["reuse"] = {"inputs": ["source.txt"], "toolchain": [[sys.executable, "--version"]]}
        return check

    def test_independent_checks_really_overlap_and_capture_logs(self):
        checks = []
        for name, other in [("one", "two"), ("two", "one")]:
            checks.append(self.check(name, f"from pathlib import Path; import time\nPath('.harness/{name}').touch()\nwhile not Path('.harness/{other}').exists(): time.sleep(.02)\nprint('{name} finished')"))
        result, receipt = self.run_plan(checks)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(receipt["status"], "passed")
        self.assertEqual(len(receipt["checks"]), 2)
        for check in receipt["checks"]:
            self.assertIn("finished", Path(check["log"]).read_text())
            self.assertGreater(check["duration_seconds"], 0)
        self.assertEqual(receipt["source"], receipt["source_after"])

    def test_failure_does_not_hide_other_results(self):
        result, receipt = self.run_plan([self.check("bad", "import sys; sys.exit(7)"), self.check("good", "print('ok')")])
        self.assertEqual(result.returncode, 1)
        checks = {c["name"]: c for c in receipt["checks"]}
        self.assertEqual(checks["bad"]["exit_code"], 7)
        self.assertEqual(checks["good"]["status"], "passed")

    def test_timeout_kills_owned_children_even_if_parent_exits_on_term(self):
        child = "import signal,time; from pathlib import Path; signal.signal(signal.SIGTERM, signal.SIG_IGN)\nwhile True:\n with Path('.harness/beats').open('a') as f: f.write('x')\n time.sleep(.02)"
        parent = f"import subprocess,sys,time; subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(30)"
        result, receipt = self.run_plan([self.check("stalled", parent, .5)])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt["checks"][0]["status"], "timeout")
        beats = self.root / ".harness" / "beats"
        size = beats.stat().st_size
        self.assertGreater(size, 0)
        time.sleep(.15)
        self.assertEqual(beats.stat().st_size, size, "a child fixture survived cleanup")

    def test_sigint_and_sigterm_cancel_the_run_without_residue_and_the_plan_runs_again(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signal.Signals(signum).name):
                suffix = signal.Signals(signum).name.lower()
                marker = self.root / ".harness" / f"{suffix}-started"
                ready = self.root / ".harness" / f"{suffix}-ready"
                beats = self.root / ".harness" / f"{suffix}-beats"
                code = (
                    "import os,signal,time\n"
                    "from pathlib import Path\n"
                    f"marker=Path({str(marker)!r}); ready=Path({str(ready)!r}); beats=Path({str(beats)!r})\n"
                    "if marker.exists():\n"
                    " print('next run completed')\n"
                    "else:\n"
                    " marker.touch()\n"
                    " signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                    " with beats.open('a') as stream: stream.write('x')\n"
                    " ready.write_text(str(os.getpid()))\n"
                    " while True:\n"
                    "  with beats.open('a') as stream: stream.write('x')\n"
                    "  time.sleep(.02)\n"
                )
                plan = self.root / ".harness" / f"{suffix}-plan.json"
                plan.write_text(json.dumps({
                    "reason": "Interrupted validation lifecycle fixture",
                    "minimum_free_gib": 0,
                    "checks": [self.check("interruptible", code, 30)],
                }))
                validation = self.root / ".harness" / "validation"
                before = set(validation.glob("*/receipt.json")) if validation.exists() else set()
                process = subprocess.Popen(
                    [sys.executable, str(SCRIPT), str(plan)], cwd=self.root,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
                )
                child_pid = None
                try:
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline and not ready.exists() and process.poll() is None:
                        time.sleep(.02)
                    self.assertTrue(ready.exists(), "the fixture check never started")
                    if ready.exists():
                        child_pid = int(ready.read_text())
                    os.kill(process.pid, signum)
                    stdout, stderr = process.communicate(timeout=10)

                    self.assertEqual(process.returncode, 128 + signum, stderr + stdout)
                    receipts = set(validation.glob("*/receipt.json")) - before
                    self.assertEqual(len(receipts), 1, stderr + stdout)
                    if len(receipts) != 1:
                        continue
                    interrupted = receipts.pop()
                    saved = json.loads(interrupted.read_text())
                    self.assertEqual(saved["status"], "cancelled")
                    self.assertEqual(saved["signal"], signal.Signals(signum).name)
                    self.assertEqual(saved["checks"][0]["status"], "cancelled")
                    self.assertEqual(list(interrupted.parent.glob("*.tmp")), [])
                    self.assertEqual(list(interrupted.parent.glob("*.lock")), [])

                    size = beats.stat().st_size
                    time.sleep(.15)
                    self.assertEqual(beats.stat().st_size, size, "an interrupted check survived cleanup")
                    with self.assertRaises(ProcessLookupError):
                        os.killpg(child_pid, 0)

                    rerun = subprocess.run(
                        [sys.executable, str(SCRIPT), str(plan), "--reuse", str(interrupted)],
                        cwd=self.root, capture_output=True, text=True, timeout=15,
                    )
                    self.assertEqual(rerun.returncode, 0, rerun.stderr + rerun.stdout)
                    rerun_receipts = set(validation.glob("*/receipt.json")) - before
                    self.assertEqual(len(rerun_receipts), 2)
                    latest = max(rerun_receipts, key=lambda path: path.stat().st_mtime_ns)
                    rerun_saved = json.loads(latest.read_text())
                    self.assertEqual(rerun_saved["status"], "passed")
                    self.assertEqual(rerun_saved["checks"][0]["status"], "passed")
                    self.assertIn("next run completed", Path(rerun_saved["checks"][0]["log"]).read_text())
                    self.assertEqual(list(validation.rglob("*.tmp")), [])
                    self.assertEqual(list(validation.rglob("*.lock")), [])
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)
                    if child_pid is not None:
                        try:
                            os.killpg(child_pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass

    def test_low_disk_blocks_before_starting_commands(self):
        result, receipt = self.run_plan([self.check("never", "from pathlib import Path; Path('.harness/ran').touch()")], minimum=10**9)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt["status"], "blocked")
        self.assertEqual(receipt["checks"][0]["status"], "not_run")
        self.assertFalse((self.root / ".harness" / "ran").exists())

    def test_source_edit_invalidates_successful_checks(self):
        result, receipt = self.run_plan([self.check("edit", "from pathlib import Path; Path('source.txt').write_text('changed')")])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt["checks"][0]["status"], "passed")
        self.assertEqual(receipt["status"], "source_changed")

    def test_untracked_file_content_is_part_of_fingerprint(self):
        new = self.root / "new.txt"
        new.write_text("one")
        before = runner.source_state(self.root)
        new.write_text("two")
        after = runner.source_state(self.root)
        self.assertEqual(before["commit"], after["commit"])
        self.assertNotEqual(before["working_changes_sha256"], after["working_changes_sha256"])
        self.assertTrue(after["dirty"])

    def test_missing_executable_is_blocked_not_passed(self):
        result, receipt = self.run_plan([{"name": "missing", "argv": ["/no/such/validation-tool"], "timeout_seconds": 1}])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt["checks"][0]["status"], "blocked")

    def test_empty_plan_and_unsafe_log_names_are_rejected(self):
        for checks in [[], [self.check("../escape", "pass")]]:
            plan = self.root / ".harness" / "invalid.json"
            plan.write_text(json.dumps({"reason": "fixture", "checks": checks}))
            with self.assertRaises(ValueError):
                runner.read_plan(plan, self.root)

    def test_passed_evidence_survives_unrelated_commit_and_keeps_original_log(self):
        check = self.counted_check()
        result, original = self.run_plan([check])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        previous = self.last_receipt
        (self.root / "notes.md").write_text("unrelated documentation\n")
        self.git("add", "notes.md")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "commit", "-qm", "docs only")
        result, receipt = self.run_plan([check], reuse=previous)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(receipt["checks"][0]["status"], "reused")
        self.assertEqual(receipt["checks"][0]["log"], original["checks"][0]["log"])
        self.assertNotEqual(receipt["source"]["commit"], original["source"]["commit"])
        self.assertEqual((self.root / ".harness/count").read_text(), "1")
        # Reuse chains retain the original execution duration, not a fictitious run.
        _, chained = self.run_plan([check], reuse=self.last_receipt)
        self.assertEqual(chained["checks"][0]["original_duration_seconds"], original["checks"][0]["duration_seconds"])

    def test_source_toolchain_environment_and_command_changes_each_rerun(self):
        check = self.counted_check()
        version = self.root / ".harness/tool-version"
        version.write_text("one")
        check["reuse"]["toolchain"] = [[sys.executable, "-c", "from pathlib import Path; print(Path('.harness/tool-version').read_text())"]]
        env = dict(os.environ, VALIDATION_FIXTURE_ENV="one")
        self.run_plan([check], env=env)
        changes = [
            lambda: (self.root / "source.txt").write_text("new source"),
            lambda: version.write_text("new toolchain"),
            lambda: env.update(VALIDATION_FIXTURE_ENV="two"),
            lambda: check["argv"].append("new argument"),
        ]
        for number, change in enumerate(changes, 2):
            previous = self.last_receipt
            change()
            result, receipt = self.run_plan([check], reuse=previous, env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(receipt["checks"][0]["status"], "passed")
            self.assertEqual((self.root / ".harness/count").read_text(), str(number))

    def test_new_and_deleted_files_in_a_declared_directory_invalidate_evidence(self):
        folder = self.root / "component"
        folder.mkdir()
        (folder / "original.txt").write_text("original")
        self.git("add", "component")
        check = self.counted_check()
        check["reuse"]["inputs"] = ["component"]
        self.run_plan([check])
        previous = self.last_receipt
        (folder / "new.txt").write_text("untracked source")
        _, receipt = self.run_plan([check], reuse=previous)
        self.assertEqual(receipt["checks"][0]["status"], "passed")
        previous = self.last_receipt
        (folder / "original.txt").unlink()
        _, receipt = self.run_plan([check], reuse=previous)
        self.assertEqual(receipt["checks"][0]["status"], "passed")
        self.assertEqual((self.root / ".harness/count").read_text(), "3")

    def test_failed_checks_rerun_without_repeating_independent_passes(self):
        good = self.counted_check()
        bad = self.check("failed", "raise SystemExit(7)")
        bad["reuse"] = good["reuse"]
        self.run_plan([good, bad])
        result, receipt = self.run_plan([good, bad], reuse=self.last_receipt)
        self.assertEqual(result.returncode, 1)
        checks = {item["name"]: item for item in receipt["checks"]}
        self.assertEqual(checks["counted"]["status"], "reused")
        self.assertEqual(checks["failed"]["status"], "failed")
        self.assertEqual((self.root / ".harness/count").read_text(), "1")

    def test_missing_or_tampered_logs_and_changing_source_are_not_reusable(self):
        check = self.counted_check()
        _, receipt = self.run_plan([check])
        previous = self.last_receipt
        Path(receipt["checks"][0]["log"]).write_text("different evidence")
        _, receipt = self.run_plan([check], reuse=previous)
        self.assertEqual(receipt["checks"][0]["status"], "passed")
        previous = self.last_receipt
        Path(receipt["checks"][0]["log"]).unlink()
        _, receipt = self.run_plan([check], reuse=previous)
        self.assertEqual(receipt["checks"][0]["status"], "passed")
        # This edit is outside the declared inputs, so only the unstable source
        # receipt (not a different per-check key) prevents reuse on the next run.
        check["argv"][2] += "; Path('unrelated.txt').write_text('changed during check')"
        _, receipt = self.run_plan([check])
        self.assertEqual(receipt["status"], "source_changed")
        _, receipt = self.run_plan([check], reuse=self.last_receipt)
        self.assertEqual(receipt["checks"][0]["status"], "passed")
        self.assertEqual((self.root / ".harness/count").read_text(), "5")

    def test_toolchain_failure_saves_a_blocked_receipt_before_tests_start(self):
        check = self.counted_check()
        check["reuse"]["toolchain"] = [[sys.executable, "-c", "raise SystemExit(4)"]]
        result, receipt = self.run_plan([check])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt["status"], "blocked")
        self.assertEqual(receipt["checks"][0]["status"], "not_run")
        self.assertFalse((self.root / ".harness/count").exists())

    def test_finished_empty_group_is_not_signaled(self):
        process = mock.Mock(pid=12345)
        process.poll.return_value = 0
        with mock.patch.object(runner.subprocess, "check_output", return_value=" 999\n"), mock.patch.object(runner.os, "killpg", side_effect=PermissionError("macOS denied")) as kill:
            self.assertIsNone(runner.stop_group(process))
            kill.assert_not_called()

    def test_finished_parent_does_not_leave_its_fixture_child_running(self):
        child = "import signal,time; from pathlib import Path; signal.signal(signal.SIGTERM, signal.SIG_IGN)\nwhile True:\n with Path('.harness/beats').open('a') as f: f.write('x')\n time.sleep(.02)"
        parent = f"import subprocess,sys,time; subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(.15)"
        result, receipt = self.run_plan([self.check("exited", parent)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        size = (self.root / ".harness/beats").stat().st_size
        self.assertGreater(size, 0)
        time.sleep(.15)
        self.assertEqual((self.root / ".harness/beats").stat().st_size, size)

    def test_cleanup_errors_preserve_results_and_cannot_report_a_pass(self):
        output = self.root / ".harness"
        with mock.patch.object(runner, "stop_group", return_value="permission denied"):
            checks = runner.run_checks({"checks": [self.check("complete", "print('all tests finished')")]}, self.root, output, 1)
        self.assertEqual(checks[0]["status"], "cleanup_failed")
        self.assertEqual(checks[0]["exit_code"], 0)
        self.assertEqual(checks[0]["cleanup_error"], "permission denied")
        self.assertIn("all tests finished", Path(checks[0]["log"]).read_text())


if __name__ == "__main__":
    unittest.main()
