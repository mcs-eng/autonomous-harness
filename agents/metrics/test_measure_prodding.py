"""Tests for Measure-Prodding.py. Run with:  python -I -m unittest

All transcript text here is synthetic.
"""
import contextlib
import datetime as dt
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "measure_prodding", HERE / "Measure-Prodding.py")
mp = importlib.util.module_from_spec(_spec)
sys.modules["measure_prodding"] = mp
_spec.loader.exec_module(mp)

UTC = dt.timezone.utc
WED = "2026-10-07T15:00:00.000Z"      # a Wednesday
SUN = "2026-10-11T12:00:00.000Z"      # a Sunday
MON = "2026-10-12T12:00:00.000Z"      # the following Monday

PHRASES = [
    "Build a page that lists open PRs",
    "approved, merge 471",
    "are you waiting on me?",
    "its empty, no tasks showing",
    "reauth'd gh",
    "CMDKEY: Credential added",
    "make me proud",
    "verbatim wrapper body",
]


def user(text, ts=WED, uuid=None, blocks=False, **extra):
    content = [{"type": "text", "text": text}] if blocks else text
    rec = {"type": "user", "timestamp": ts, "isSidechain": False,
           "message": {"role": "user", "content": content}}
    if uuid:
        rec["uuid"] = uuid
    rec.update(extra)
    return rec


def write_session(root, project, name, records):
    folder = Path(root) / project
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (name + ".jsonl")
    with open(path, "w", encoding="utf-8") as fh:
        for rec in records:
            fh.write(json.dumps(rec) + "\n")
    return path


def build_fixture(root):
    """Two synthetic sessions covering every kind of record in the brief."""
    write_session(root, "C--Users-someone-dev-alpha", "session-one", [
        user("Build a page that lists open PRs", uuid="a1"),
        user("approved, merge 471", uuid="a2", blocks=True),
        user("are you waiting on me?", uuid="a3"),
        user("its empty, no tasks showing - thats what I am trying to tell you",
             uuid="a4"),
        user("User's message, verbatim: approved, continue, yes", uuid="a5"),
        user("approved, sidechain must be skipped", uuid="a6", isSidechain=True),
        {"type": "user", "timestamp": WED, "uuid": "a7", "isSidechain": False,
         "message": {"role": "user", "content": [
             {"type": "tool_result", "tool_use_id": "t1",
              "content": "approved, continue"}]}},
        {"type": "assistant", "timestamp": WED, "uuid": "a8",
         "message": {"role": "assistant", "content": "approved, continue"}},
    ])
    write_session(root, "C--Users-someone-dev-beta", "session-two", [
        user("i have reauth'd gh like 10 times today", uuid="b1"),
        user("CMDKEY: Credential added successfully.", uuid="b2"),
        user("going to bed, make me proud", uuid="b3"),
        user("<task-notification>approved continue</task-notification>",
             uuid="b4"),
    ])


def run_main(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = mp.main(argv)
    return code, out.getvalue(), err.getvalue()


def fixture_args(root, *extra):
    return ["--projects-dir", str(root), "--since", "2026-10-01",
            "--until", "2026-10-31", "--utc", *extra]


class CountsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        build_fixture(self.root)

    def totals(self):
        code, out, _ = run_main(fixture_args(self.root, "--json"))
        self.assertEqual(code, 0)
        return json.loads(out)

    def test_exact_bucket_counts(self):
        t = self.totals()["totals"]
        expected = {"sessions": 2, "typed_turns": 7, "dispatch": 1,
                    "approve": 1, "nudge": 1, "verify": 1, "route": 0,
                    "resupply": 0, "hygiene": 1, "handstep": 1, "handoff": 1,
                    "any_prodding": 6, "prodding_share": 85.7}
        for key, value in expected.items():
            self.assertEqual(t[key], value, key)

    def test_one_week_row_matches_totals(self):
        data = self.totals()
        self.assertEqual(len(data["weeks"]), 1)
        self.assertEqual(data["weeks"][0]["week"], "2026-10-05")
        self.assertEqual(data["weeks"][0]["any_prodding"], 6)

    def test_skips_are_counted_not_typed(self):
        skipped = self.totals()["skipped"]
        self.assertEqual(skipped.get("skipped_prefix"), 1)

    def test_classify_each_phrase(self):
        self.assertEqual(mp.classify("Build a page that lists open PRs"), set())
        self.assertEqual(mp.classify("approved, merge 471"), {"approve"})
        self.assertEqual(mp.classify("are you waiting on me?"), {"nudge"})
        self.assertEqual(mp.classify("its empty, no tasks showing"), {"verify"})
        self.assertEqual(mp.classify("i have reauth'd gh like 10 times today"),
                         {"hygiene"})
        self.assertEqual(mp.classify("CMDKEY: Credential added successfully."),
                         {"handstep"})
        self.assertEqual(mp.classify("going to bed, make me proud"),
                         {"handoff"})

    def test_pattern_edges(self):
        self.assertEqual(mp.classify("Yes."), {"approve"})
        self.assertEqual(mp.classify("yes, but add a test"), set())
        self.assertEqual(mp.classify("go"), {"nudge"})
        self.assertEqual(mp.classify("Use opus for this lane"), {"route"})
        self.assertEqual(mp.classify("opus wrote this"), set())
        self.assertEqual(mp.classify("it didn\u2019t work"), {"verify"})
        self.assertEqual(mp.classify("ok"), {"handstep"})
        self.assertEqual(mp.classify("we decided this, again"), {"resupply"})
        self.assertEqual(mp.classify("again please"), set())

    def test_long_turns(self):
        root = Path(self.tmp.name) / "long"
        write_session(root, "C--Users-someone-dev-gamma", "s", [
            user("approved " + "x" * 800, uuid="l1"),        # typed, not bucketed
            user("approved " + "x" * 4100, uuid="l2"),       # paste: skipped
        ])
        code, out, _ = run_main(fixture_args(root, "--json"))
        data = json.loads(out)
        self.assertEqual(data["totals"]["typed_turns"], 1)
        self.assertEqual(data["totals"]["approve"], 0)
        self.assertEqual(data["skipped"]["too_long_paste"], 1)

    def test_duplicate_uuid_counts_once(self):
        root = Path(self.tmp.name) / "dups"
        rec = user("approved", uuid="same")
        write_session(root, "C--Users-someone-dev-delta", "first", [rec])
        write_session(root, "C--Users-someone-dev-delta", "copy", [rec])
        _, out, _ = run_main(fixture_args(root, "--json"))
        data = json.loads(out)
        self.assertEqual(data["totals"]["typed_turns"], 1)
        self.assertEqual(data["skipped"]["duplicate_record"], 1)

    def test_system_injected_turns_are_not_typed(self):
        root = Path(self.tmp.name) / "sys"
        write_session(root, "C--Users-someone-dev-eps", "s", [
            user("approved", uuid="m1", isMeta=True),
            user("approved", uuid="m2", origin={"kind": "peer"}),
            user("approved", uuid="m3", origin={"kind": "human"}),
        ])
        _, out, _ = run_main(fixture_args(root, "--json"))
        self.assertEqual(json.loads(out)["totals"]["typed_turns"], 1)


class WeekTest(unittest.TestCase):
    def test_week_start_is_monday(self):
        sunday = dt.date(2026, 10, 11)
        monday = dt.date(2026, 10, 12)
        self.assertEqual(mp.week_start(sunday), dt.date(2026, 10, 5))
        self.assertEqual(mp.week_start(monday), dt.date(2026, 10, 12))
        self.assertNotEqual(mp.week_start(sunday), mp.week_start(monday))

    def test_sunday_and_monday_land_in_different_weeks(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_session(tmp, "C--Users-someone-dev-zeta", "s", [
                user("Build a page", ts=SUN, uuid="w1"),
                user("approved", ts=MON, uuid="w2"),
            ])
            code, out, _ = run_main(fixture_args(tmp, "--json"))
            weeks = json.loads(out)["weeks"]
            self.assertEqual([w["week"] for w in weeks],
                             ["2026-10-05", "2026-10-12"])
            self.assertEqual([w["typed_turns"] for w in weeks], [1, 1])
            self.assertEqual([w["any_prodding"] for w in weeks], [0, 1])

    def test_empty_weeks_between_data_are_filled(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_session(tmp, "C--Users-someone-dev-zeta", "s", [
                user("Build a page", ts="2026-10-05T10:00:00Z", uuid="w1"),
                user("approved", ts="2026-10-19T10:00:00Z", uuid="w2"),
            ])
            _, out, _ = run_main(fixture_args(tmp, "--json"))
            weeks = json.loads(out)["weeks"]
            self.assertEqual([w["week"] for w in weeks],
                             ["2026-10-05", "2026-10-12", "2026-10-19"])
            self.assertIsNone(weeks[1]["prodding_share"])


class PrivacyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        build_fixture(self.root)

    def assert_no_text(self, text):
        for phrase in PHRASES:
            self.assertNotIn(phrase.lower(), text.lower())

    def test_default_output_has_no_transcript_text(self):
        _, out, err = run_main(fixture_args(self.root))
        self.assert_no_text(out + err)

    def test_json_and_by_project_have_no_transcript_text(self):
        _, out, err = run_main(fixture_args(self.root, "--json", "--by-project"))
        self.assert_no_text(out + err)
        _, out, err = run_main(fixture_args(self.root, "--by-project"))
        self.assert_no_text(out + err)

    def test_explain_is_required_to_see_text(self):
        code, out, _ = run_main(fixture_args(self.root, "--explain", "approve"))
        self.assertEqual(code, 0)
        self.assertIn("approved, merge 471", out)
        warning_at = out.index("WARNING")
        self.assertLess(warning_at, out.index("approved, merge 471"))
        self.assertIn("personal", out[warning_at:out.index("\n", warning_at)])

    def test_explain_snippets_are_short_and_limited(self):
        root = Path(self.tmp.name) / "many"
        write_session(root, "C--Users-someone-dev-eta", "s", [
            user("please approve this change " + "z" * 200 + " %d" % i,
                 ts="2026-10-07T%02d:00:00Z" % (i % 24), uuid="e%d" % i)
            for i in range(30)])
        _, out, _ = run_main(fixture_args(root, "--json", "--explain", "approve"))
        snippets = json.loads(out)["explain"]["snippets"]
        self.assertEqual(len(snippets), 20)
        self.assertTrue(all(len(s) <= 60 for s in snippets))
        self.assertTrue(all("approve" in s for s in snippets))

    def test_explain_rejects_unknown_bucket(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                mp.main(fixture_args(self.root, "--explain", "nonsense"))


class OptionsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "projects"
        build_fixture(self.root)
        self.base = Path(self.tmp.name) / "baseline.json"

    def test_by_project_uses_short_names(self):
        data = json.loads(run_main(fixture_args(self.root, "--json",
                                                "--by-project"))[1])
        names = {p["project"]: p for p in data["projects"]}
        self.assertEqual(set(names), {"alpha", "beta"})
        self.assertEqual(names["alpha"]["typed_turns"], 4)
        self.assertEqual(names["beta"]["typed_turns"], 3)

    def test_short_project_name(self):
        short = mp.short_project_name
        self.assertEqual(short("C--Users-someone-dev-autonomous-harness"),
                         "autonomous-harness")
        self.assertEqual(
            short("C--Users-someone-dev-estate--claude-worktrees-calm-x-1a2b3c"),
            "estate")
        self.assertEqual(short("M--localWiki"), "localWiki")
        self.assertEqual(short("C:\\work\\repo"), "repo")

    def test_baseline_refuses_overwrite_unless_forced(self):
        args = fixture_args(self.root, "--baseline", str(self.base))
        self.assertEqual(run_main(args)[0], 0)
        saved = json.loads(self.base.read_text(encoding="utf-8"))
        self.assertEqual(saved["typed_turns"], 7)
        self.assertEqual(saved["any_prodding"], 6)
        self.base.write_text("keep me", encoding="utf-8")
        code, _, err = run_main(args)
        self.assertEqual(code, 2)
        self.assertIn("--force", err)
        self.assertEqual(self.base.read_text(encoding="utf-8"), "keep me")
        self.assertEqual(run_main(args + ["--force"])[0], 0)
        self.assertEqual(json.loads(self.base.read_text(encoding="utf-8"))
                         ["typed_turns"], 7)

    def test_baseline_refuses_transcript_folder_and_non_json(self):
        inside = Path(self.root) / "baseline.json"
        code, _, err = run_main(fixture_args(self.root, "--baseline", str(inside)))
        self.assertEqual(code, 2)
        self.assertIn("projects directory", err)
        self.assertFalse(inside.exists())
        bad = Path(self.tmp.name) / "baseline.jsonl"
        code, _, err = run_main(fixture_args(self.root, "--baseline", str(bad)))
        self.assertEqual(code, 2)
        self.assertIn(".json", err)
        self.assertFalse(bad.exists())

    def test_table_has_header_and_total_row(self):
        code, out, _ = run_main(fixture_args(self.root))
        self.assertEqual(code, 0)
        lines = out.splitlines()
        header = next(l for l in lines if l.startswith("week"))
        self.assertEqual(header.split(), ["week"] + mp.COLUMNS)
        total = next(l for l in lines if l.startswith("total"))
        self.assertIn("85.7%", total)

    def test_date_range_excludes_outside_turns(self):
        args = ["--projects-dir", str(self.root), "--since", "2026-10-08",
                "--until", "2026-10-31", "--utc", "--json"]
        data = json.loads(run_main(args)[1])
        self.assertEqual(data["totals"]["typed_turns"], 0)


if __name__ == "__main__":
    unittest.main()
