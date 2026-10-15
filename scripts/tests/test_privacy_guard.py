"""Privacy guard tests. Terms in this file are fake stand-ins, not real names."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "privacy-guard.py"
HOOK = ROOT / "scripts" / "hooks" / "commit-msg"
spec = importlib.util.spec_from_file_location("privacy_guard", SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

FAKE_TERMS = ["examplehost", "sampleboard", "exam"]


def combined(result):
    return result.stdout + result.stderr


class ParseTests(unittest.TestCase):
    def test_newline_and_comma_lists_drop_blanks(self):
        self.assertEqual(guard.parse_terms("examplehost\nsampleboard\n"), ["examplehost", "sampleboard"])
        self.assertEqual(guard.parse_terms("examplehost, sampleboard"), ["examplehost", "sampleboard"])
        self.assertEqual(guard.parse_terms("examplehost,\nsampleboard"), ["examplehost", "sampleboard"])
        self.assertEqual(guard.parse_terms("\n,\n  ,"), [])

    def test_comment_lines_are_ignored(self):
        self.assertEqual(guard.parse_terms("# heading\n  # indented\nexamplehost\n"), ["examplehost"])
        self.assertEqual(guard.parse_terms("\ufeff# first\nsampleboard, examplehost"), ["sampleboard", "examplehost"])

    def test_duplicate_terms_collapse_case_insensitively(self):
        self.assertEqual(guard.parse_terms("ExampleHost\nexamplehost"), ["ExampleHost"])


class MatchTests(unittest.TestCase):
    def test_case_insensitive_word_match(self):
        self.assertTrue(guard.contains_term("See ExampleHost today", ["examplehost"]))
        self.assertTrue(guard.contains_term("examplehost", ["ExampleHost"]))
        self.assertTrue(guard.contains_term("(sampleboard)", ["sampleboard"]))
        self.assertTrue(guard.contains_term("sampleboard.", ["sampleboard"]))

    def test_word_boundary_does_not_match_inside_a_longer_word(self):
        self.assertFalse(guard.contains_term("update the example", ["exam"]))
        self.assertFalse(guard.contains_term("exams", ["exam"]))
        self.assertFalse(guard.contains_term("reexam", ["exam"]))
        self.assertTrue(guard.contains_term("the exam name", ["exam"]))
        self.assertTrue(guard.contains_term("exam", ["exam"]))

    def test_metacharacters_are_literal(self):
        self.assertTrue(guard.contains_term("use sample.board now", ["sample.board"]))
        self.assertFalse(guard.contains_term("use sampleXboard now", ["sample.board"]))
        self.assertTrue(guard.contains_term("host[1]", ["host[1]"]))
        self.assertFalse(guard.contains_term("host1", ["host[1]"]))

    def test_redaction_removes_the_term_from_a_location(self):
        rendered = guard.redact("file examplehost.txt line 1", ["examplehost", "sampleboard"])
        self.assertEqual(rendered, "file [redacted].txt line 1")
        self.assertNotIn("examplehost", rendered.lower())


class DiffTests(unittest.TestCase):
    def test_added_lines_keep_new_file_line_numbers_and_skip_removals(self):
        diff = textwrap.dedent("""\
            diff --git a/notes.txt b/notes.txt
            index 1111111..2222222 100644
            --- a/notes.txt
            +++ b/notes.txt
            @@ -2 +2 @@
            -examplehost
            +public
            @@ -4,0 +5 @@
            +sampleboard
            """)
        self.assertEqual(list(guard.added_lines(diff)), [
            ("notes.txt", 2, "public"),
            ("notes.txt", 5, "sampleboard"),
        ])

    def test_added_lines_that_look_like_headers_are_still_scanned(self):
        diff = (
            "diff --git a/notes.md b/notes.md\n"
            "--- a/notes.md\n"
            "+++ b/notes.md\n"
            "@@ -1,1 +1,4 @@\n"
            " keep\n"
            "+++ looks like a header\n"
            "+diff --git looks like a file\n"
            "+examplehost after them\n"
        )
        self.assertEqual(list(guard.added_lines(diff)), [
            ("notes.md", 2, "++ looks like a header"),
            ("notes.md", 3, "diff --git looks like a file"),
            ("notes.md", 4, "examplehost after them"),
        ])

    def test_form_feed_and_line_separator_do_not_split_an_added_line(self):
        diff = (
            "+++ b/notes.txt\n"
            "@@ -0,0 +1,2 @@\n"
            "+public\x0cexamplehost\n"
            "+public\u2028sampleboard\r\n"
        )
        lines = list(guard.added_lines(diff))
        self.assertEqual([line_no for _, line_no, _ in lines], [1, 2])
        self.assertTrue(guard.contains_term(lines[0][2], ["examplehost"]))
        self.assertTrue(guard.contains_term(lines[1][2], ["sampleboard"]))

    def test_annotation_text_escapes_workflow_command_characters(self):
        self.assertEqual(guard.annotation_text("a%b\rc\nd"), "a%25b%0Dc%0Ad")

    def test_quoted_git_paths_decode_utf8_octal_escapes(self):
        self.assertEqual(guard.unquote_git_path("q\\303\\274nal.txt"), "q\u00fcnal.txt")
        self.assertEqual(guard.unquote_git_path('a\\"b\\\\c\\td'), 'a"b\\c\td')
        header = '+++ "b/q\\303\\274nal.txt"'
        path = guard.destination_path(header)
        self.assertEqual(path, "q\u00fcnal.txt")
        self.assertEqual(guard.redact(f"file {path} line 1", ["q\u00fcnal"]), "file [redacted].txt line 1")

    def test_non_ascii_terms_match_case_insensitively(self):
        self.assertTrue(guard.contains_term("Über alles", ["\u00fcber"]))
        self.assertFalse(guard.contains_term("Überhaupt", ["\u00fcber"]))

    def test_control_characters_in_a_location_are_replaced(self):
        self.assertEqual(guard.safe_line("file ok\n::notice::x line 1"), "file ok?::notice::x line 1")

    def test_new_file_lines_are_added(self):
        diff = textwrap.dedent("""\
            diff --git a/notes.txt b/notes.txt
            new file mode 100644
            --- /dev/null
            +++ b/notes.txt
            @@ -0,0 +1,2 @@
            +example update
            +sampleboard
            """)
        self.assertEqual(list(guard.added_lines(diff)), [
            ("notes.txt", 1, "example update"),
            ("notes.txt", 2, "sampleboard"),
        ])


class RepositoryScanTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "fixture@example.test")
        self.git("config", "user.name", "Fixture")
        self.git("config", "commit.gpgsign", "false")
        self.write("README.md", "hello example\n")
        self.base = self.commit("base")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.PIPE, text=True).strip()

    def write(self, path, value):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def scan(self, head, title="", body="", terms=None, base=None):
        return guard.scan_pull_request(
            self.root, base or self.base, head, title, body, terms if terms is not None else FAKE_TERMS)

    def test_match_in_each_location_and_word_boundary_on_added_lines(self):
        self.write("notes.txt", "hello example\nuses sampleboard today\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "subject line", "-m", "note examplehost in the lab")
        head = self.git("rev-parse", "HEAD")
        findings = self.scan(head, title="Ship ExampleHost", body="See sampleboard.\n")
        self.assertEqual(findings, [
            "PR title: [redacted 11 chars]",
            "PR body: [redacted 11 chars]",
            f"commit {head} message: [redacted 11 chars]",
            "file notes.txt line 2 column 6: [redacted 11 chars]",
        ])
        rendered = "\n".join(findings).lower()
        self.assertNotIn("examplehost", rendered)
        self.assertNotIn("sampleboard", rendered)

    def test_removed_lines_are_not_scanned(self):
        self.write("notes.txt", "examplehost\n")
        parent = self.commit("add a placeholder")
        self.write("notes.txt", "public\n")
        head = self.commit("replace a line")
        self.assertEqual(self.scan(head, terms=["examplehost"], base=parent), [])

    def test_term_inside_a_path_is_not_printed(self):
        self.write("examplehost.txt", "sampleboard\n")
        head = self.commit("public change")
        findings = self.scan(head, terms=["examplehost", "sampleboard"])
        self.assertEqual(findings, ["file [redacted].txt line 1 column 1: [redacted 11 chars]"])
        rendered = "\n".join(findings).lower()
        self.assertNotIn("examplehost", rendered)
        self.assertNotIn("sampleboard", rendered)

    def test_lone_carriage_return_does_not_hide_later_lines(self):
        self.write("notes.txt", "public\rmore\nexamplehost\nsampleboard\n")
        head = self.commit("public change")
        findings = self.scan(head, terms=["examplehost", "sampleboard"])
        self.assertEqual(findings, [
            "file notes.txt line 2 column 1: [redacted 11 chars]",
            "file notes.txt line 3 column 1: [redacted 11 chars]",
        ])

    def test_clean_text_passes(self):
        self.write("notes.txt", "hello example\n")
        head = self.commit("update the example")
        self.assertEqual(self.scan(head, title="Public notes", body="No private names.\n"), [])


class CliTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.env = os.environ.copy()
        self.env.pop("PRIVATE_TERMS", None)
        self.env.pop("PRIVATE_TERMS_FILE", None)
        self.env.pop("GITHUB_ACTIONS", None)
        self.env.pop("PR_TITLE", None)
        self.env.pop("PR_BODY", None)

    def run_guard(self, args, env=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=self.root,
            env=env or self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_unset_secret_warns_and_passes_without_printing_input(self):
        self.env["PR_TITLE"] = "examplehost"
        result = self.run_guard(["--pull-request"])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("warning", result.stderr.lower())
        self.assertNotIn("examplehost", combined(result).lower())

    def test_empty_secret_warns_and_passes(self):
        self.env["PRIVATE_TERMS"] = " \n,"
        self.env["PR_TITLE"] = "sampleboard"
        self.env["PR_BODY"] = "examplehost"
        result = self.run_guard(["--pull-request"])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("PRIVATE_TERMS and PRIVATE_TERMS_FILE are unset or empty", result.stderr)
        self.assertNotIn("sampleboard", combined(result).lower())
        self.assertNotIn("examplehost", combined(result).lower())

    def test_pull_request_mode_does_not_read_the_local_term_file(self):
        home = self.root / "home"
        config = home / ".config"
        config.mkdir(parents=True)
        (config / "private-terms.txt").write_text("examplehost\n")
        self.env["HOME"] = str(home)
        self.env["PR_TITLE"] = "examplehost"
        result = self.run_guard(["--pull-request"])
        self.assertEqual(result.returncode, 0)
        self.assertIn("warning", result.stderr.lower())
        self.assertNotIn("examplehost", combined(result).lower())

    def test_cli_prints_only_locations_for_a_comma_separated_list(self):
        repo = self.root / "repo"
        repo.mkdir()
        git = lambda *args: subprocess.check_output(["git", *args], cwd=repo, stderr=subprocess.PIPE, text=True).strip()
        git("init", "-q", "-b", "main")
        git("config", "user.email", "fixture@example.test")
        git("config", "user.name", "Fixture")
        git("config", "commit.gpgsign", "false")
        (repo / "README.md").write_text("hello example\n")
        git("add", "-A")
        git("commit", "-q", "-m", "base")
        base = git("rev-parse", "HEAD")
        (repo / "notes.txt").write_text("ExampleHost\n")
        git("add", "-A")
        git("commit", "-q", "-m", "public change")
        head = git("rev-parse", "HEAD")
        self.env["PRIVATE_TERMS"] = "examplehost, sampleboard"
        self.env["BASE_SHA"] = base
        self.env["HEAD_SHA"] = head
        self.env["PR_TITLE"] = "Public title"
        self.env["PR_BODY"] = "mentions sampleboard once"
        result = self.run_guard(["--pull-request", "--repo", str(repo)])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines(), [
            "PR body: [redacted 11 chars]",
            "file notes.txt line 1 column 1: [redacted 11 chars]",
        ])
        self.assertEqual(result.stderr, "")
        rendered = combined(result).lower()
        self.assertNotIn("examplehost", rendered)
        self.assertNotIn("sampleboard", rendered)

    def test_commit_message_file_prints_only_the_location(self):
        terms = self.root / "terms.txt"
        terms.write_text("examplehost\nsampleboard\n")
        message = self.root / "COMMIT_MSG"
        message.write_text("subject\n\nTouch examplehost.\n")
        result = self.run_guard(["--terms-file", str(terms), "--commit-message-file", str(message)])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "commit message: [redacted 11 chars]\n")
        self.assertNotIn("examplehost", combined(result).lower())

    def test_pull_request_mode_reads_private_terms_file_with_comments(self):
        repo = self.root / "repo"
        repo.mkdir()
        git = lambda *args: subprocess.check_output(["git", *args], cwd=repo, stderr=subprocess.PIPE, text=True).strip()
        git("init", "-q", "-b", "main")
        git("config", "user.email", "fixture@example.test")
        git("config", "user.name", "Fixture")
        git("config", "commit.gpgsign", "false")
        (repo / "README.md").write_text("hello\n")
        git("add", "-A")
        git("commit", "-q", "-m", "base")
        base = git("rev-parse", "HEAD")
        (repo / "notes.txt").write_text("public\nsee examplehost here\n# commentword\n")
        git("add", "-A")
        git("commit", "-q", "-m", "public change")
        head = git("rev-parse", "HEAD")
        terms = self.root / "terms.txt"
        terms.write_text("# commentword\n  # another comment\nexamplehost\n")
        self.env["PRIVATE_TERMS_FILE"] = str(terms)
        self.env["BASE_SHA"] = base
        self.env["HEAD_SHA"] = head
        self.env["PR_TITLE"] = "Public title"
        self.env["PR_BODY"] = "commentword is not a term"
        result = self.run_guard(["--pull-request", "--repo", str(repo)])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines(), [
            "file notes.txt line 2 column 5: [redacted 11 chars]",
        ])
        self.assertNotIn("examplehost", combined(result).lower())

    def test_private_terms_env_wins_over_private_terms_file(self):
        terms = self.root / "terms.txt"
        terms.write_text("examplehost\n")
        self.env["PRIVATE_TERMS_FILE"] = str(terms)
        self.env["PRIVATE_TERMS"] = "sampleboard"
        self.env["BASE_SHA"] = "x"
        self.env["HEAD_SHA"] = "y"
        args = guard.parse_args(["--pull-request"])
        old = os.environ.copy()
        try:
            os.environ.clear()
            os.environ.update(self.env)
            self.assertEqual(guard.load_pr_terms(args), ["sampleboard"])
            os.environ["PRIVATE_TERMS"] = ""
            self.assertEqual(guard.load_pr_terms(args), ["examplehost"])
        finally:
            os.environ.clear()
            os.environ.update(old)

    def test_actions_annotations_do_not_print_the_term(self):
        terms = self.root / "terms.txt"
        terms.write_text("examplehost\n")
        message = self.root / "COMMIT_MSG"
        message.write_text("Touch examplehost.\n")
        self.env["GITHUB_ACTIONS"] = "true"
        result = self.run_guard(["--terms-file", str(terms), "--commit-message-file", str(message)])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "::error::commit message: [redacted 11 chars]\n")
        self.assertNotIn("examplehost", combined(result).lower())

    def test_commit_message_file_allows_a_longer_word(self):
        terms = self.root / "terms.txt"
        terms.write_text("exam\n")
        message = self.root / "COMMIT_MSG"
        message.write_text("update the example\n")
        result = self.run_guard(["--terms-file", str(terms), "--commit-message-file", str(message)])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


class HookTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.home = self.root / "home"
        (self.home / ".config").mkdir(parents=True)
        self.message = self.root / "COMMIT_MSG"
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.home)
        self.env.pop("PRIVATE_TERMS_FILE", None)
        self.env.pop("PRIVATE_TERMS", None)
        self.env.pop("GITHUB_ACTIONS", None)

    def run_hook(self):
        return subprocess.run(
            ["sh", str(HOOK), str(self.message)],
            cwd=ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_hook_does_nothing_when_neither_term_file_exists(self):
        self.message.write_text("examplehost\n")
        self.env["PRIVATE_TERMS"] = "examplehost"
        result = self.run_hook()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(combined(result), "")

    def test_hook_reads_the_home_file_and_hides_the_term(self):
        (self.home / ".config" / "private-terms.txt").write_text("examplehost,sampleboard\n")
        self.message.write_text("Ship SampleBoard\n")
        result = self.run_hook()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "commit message: [redacted 11 chars]\n")
        self.assertNotIn("sampleboard", combined(result).lower())
        self.assertNotIn("examplehost", combined(result).lower())

    def test_hook_reads_the_privacy_guard_default_file_first(self):
        folder = self.home / ".config" / "privacy-guard"
        folder.mkdir()
        (folder / "private-terms.txt").write_text("# comment line\nexamplehost\n")
        (self.home / ".config" / "private-terms.txt").write_text("sampleboard\n")
        self.message.write_text("sampleboard only\n")
        self.assertEqual(self.run_hook().returncode, 0)
        self.message.write_text("touch examplehost\n")
        result = self.run_hook()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "commit message: [redacted 11 chars]\n")
        self.assertNotIn("examplehost", combined(result).lower())

    def test_hook_word_boundary(self):
        (self.home / ".config" / "private-terms.txt").write_text("exam\n")
        self.message.write_text("update the example\n")
        result = self.run_hook()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_explicit_term_file_overrides_the_home_file(self):
        (self.home / ".config" / "private-terms.txt").write_text("sampleboard\n")
        chosen = self.root / "chosen.txt"
        chosen.write_text("examplehost\n")
        self.env["PRIVATE_TERMS_FILE"] = str(chosen)
        self.message.write_text("sampleboard only\n")
        result = self.run_hook()
        self.assertEqual(result.returncode, 0)
        self.message.write_text("examplehost only\n")
        result = self.run_hook()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "commit message: [redacted 11 chars]\n")
        self.assertNotIn("examplehost", combined(result).lower())

    def test_missing_explicit_file_falls_back_to_the_home_file(self):
        (self.home / ".config" / "private-terms.txt").write_text("examplehost\n")
        self.env["PRIVATE_TERMS_FILE"] = str(self.root / "missing.txt")
        self.message.write_text("examplehost\n")
        result = self.run_hook()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("examplehost", combined(result).lower())


def repo_text(path):
    """Read a repo file from the worktree, or from HEAD when it is not checked out.

    Process checks use a sparse checkout that omits these paths. The blobs are
    still in the commit, so git show works there after the change is committed.
    """
    file = ROOT / path
    if file.is_file():
        return file.read_text()
    return subprocess.check_output(["git", "show", f"HEAD:{path}"], cwd=ROOT, text=True)


class PolicyFileTests(unittest.TestCase):
    def test_workflow_covers_drafts_and_documents_fork_secrets(self):
        text = repo_text(".github/workflows/privacy-guard.yml")
        # The secret is only given to base-branch code: pull_request_target,
        # with no step that checks out or runs the pull request head.
        self.assertIn("pull_request_target:", text)
        self.assertIn("head.repo.full_name == github.repository && secrets.PRIVATE_TERMS || ''", text)
        self.assertNotIn("github.event.pull_request.head.ref", text)
        self.assertNotIn("ref: ${{", text)
        self.assertNotIn("$RUNNER_TEMP", text)
        for kind in ("opened", "edited", "synchronize", "reopened", "ready_for_review"):
            self.assertIn(kind, text)
        self.assertIn("secrets.PRIVATE_TERMS", text)
        self.assertIn("scripts/privacy-guard.py", text)
        self.assertIn("fork", text.lower())
        self.assertNotIn("draft == false", text)
        self.assertIn("persist-credentials: false", text)
        self.assertIn("python3 scripts/privacy-guard.py --pull-request", text)

    def test_agent_rules_and_install_note(self):
        rule = repo_text(".cursor/rules/public-repo.mdc")
        self.assertIn("alwaysApply: true", rule)
        self.assertIn("This repository is public.", rule)
        for path in ("AGENTS.md", "CONTRIBUTING.md"):
            text = repo_text(path)
            self.assertIn("core.hooksPath scripts/hooks", text)
            self.assertIn("PRIVATE_TERMS_FILE", text)
            self.assertIn("~/.config/private-terms.txt", text)
            self.assertIn("~/.config/privacy-guard/private-terms.txt", text)


if __name__ == "__main__":
    unittest.main()
