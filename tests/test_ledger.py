"""Runs the real SQL against a real PostgreSQL whose tables are built from the plugin schemas.

Set LEDGER_TEST_DB to a scratch database. Without it the database tests are skipped.
"""
import contextlib, io, json, os, pathlib, sys, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import ledger  # noqa: E402

DB = os.environ.get("LEDGER_TEST_DB")

EXPECTED_DAY1 = {
    ("NET-01", "sg-demo-jump"), ("NET-01", "sg-demo-v6"), ("STO-01", "meridian-demo-marketing-drop"),
    ("DB-01", "reporting-poc"), ("ENC-01", "vol-demo-orphan"), ("COST-01", "vol-demo-orphan"),
    ("COST-02", "eipalloc-demo-idle"),
    ("NET-01", "rg-treasury/nsg-demo-rdp"), ("NET-01", "rg-treasury/nsg-demo-range"),
    ("STO-02", "rg-treasury/meridiandemolegacy"), ("DB-01", "rg-treasury/sql-demo-fx"),
    ("DB-02", "rg-treasury/sql-demo-fx"), ("COST-01", "rg-treasury/disk-old-migration"),
    ("COST-02", "rg-treasury/pip-demo-spare"), ("COST-03", "vm-demo-0002"),
    ("NET-01", "allow-all-temp"), ("STO-01", "meridian-demo-share"), ("DB-01", "risk-models"),
    ("COST-01", "europe-west1-b/etl-temp"), ("COST-02", "europe-west1/forgotten-ip"),
}


def quietly(fn, *args, **kwargs):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return fn(*args, **kwargs)


@unittest.skipUnless(DB, "set LEDGER_TEST_DB to run")
class Pipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dir = pathlib.Path(cls.tmp.name)
        cls.snap = {}
        for day in (1, 2):
            quietly(ledger.load_demo, DB, day)
            cls.snap[day] = quietly(ledger.collect, DB, cls.dir / f"{day}.json", ledger.CLOUDS, schema="ledger_demo")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def found(self, day):
        return {(f["control"], f["resource_id"]) for f in self.snap[day]["findings"]}

    def test_every_planted_issue_and_nothing_else(self):
        self.assertEqual(self.snap[1]["errors"], [])
        self.assertEqual(self.found(1), EXPECTED_DAY1)

    def test_inventory_counts(self):
        self.assertEqual(len(self.snap[1]["inventory"]), 33)

    def test_tag_keys_are_normalised_across_clouds(self):
        by_name = {r["name"]: r for r in self.snap[1]["inventory"]}
        for name in ("payments-api-1", "treasury-app-01", "analytics-worker-1"):
            self.assertTrue(by_name[name]["cost_center"], name)

    def test_drift(self):
        d = ledger.diff(self.snap[1], self.snap[2])
        self.assertEqual({(f["control"], f["resource_id"]) for f in d["new_findings"]},
                         {("STO-01", "meridian-demo-vendor-upload")})
        self.assertEqual({f["resource_id"] for f in d["gone_findings"]},
                         {"sg-demo-jump", "rg-treasury/disk-old-migration"})
        self.assertIn("i-demo-new99", {r["resource_id"] for r in d["new_resources"]})

    def test_failed_cloud_is_not_reported_as_fixed(self):
        broken = json.loads(json.dumps(self.snap[2]))
        broken["findings"] = [f for f in broken["findings"] if f["cloud"] != "gcp"]
        broken["errors"] = [{"query": "findings/gcp.sql", "error": "403"}]
        d = ledger.diff(self.snap[1], broken)
        self.assertEqual(d["skipped"], ["gcp"])
        self.assertFalse([f for f in d["gone_findings"] if f["cloud"] == "gcp"])

    def test_missing_table_marks_snapshot_incomplete(self):
        snap = quietly(ledger.collect, DB, self.dir / "x.json", ["aws"], schema="no_such_schema")
        self.assertEqual(len(snap["errors"]), 2)

    def test_collection_session_is_read_only(self):
        with self.assertRaises(RuntimeError):
            ledger.psql(DB, "create table should_not_exist(x int);")

    def test_hostile_values_are_neutralised_in_outputs(self):
        snap = json.loads(json.dumps(self.snap[1]))
        row = snap["inventory"][0]
        row["owner"] = '=HYPERLINK("http://x")</script><img src=x>'
        row["account"] = 'a"]; click c0 "javascript:1'
        path = self.dir / "hostile.json"
        path.write_text(json.dumps(snap))
        quietly(ledger.report, path, self.dir / "h")
        self.assertIn("'=HYPERLINK", (self.dir / "h" / "inventory.csv").read_text())
        self.assertNotIn("</script><img", (self.dir / "h" / "dashboard.html").read_text())
        self.assertNotIn('a"]', (self.dir / "h" / "estate.mmd").read_text())

    def test_gate_exit_code(self):
        args = ["report", str(self.dir / "1.json"), "--out", str(self.dir / "g"), "--fail-on", "critical"]
        self.assertEqual(quietly(ledger.main, args), 2)


if __name__ == "__main__":
    unittest.main()
