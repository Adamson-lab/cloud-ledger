#!/usr/bin/env python3
"""cloud-ledger: snapshot a multicloud estate through Steampipe and report on it.

  collect    run the SQL packs against a database and save a snapshot
  report     build report.md, inventory.csv, dashboard.html and an estate diagram from a snapshot
  load-demo  load fictional sample data into schema "ledger_demo" of a scratch Postgres

Needs Python 3.10+ and the psql client. No Python packages.
"""
import argparse, collections, csv, datetime, json, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent
CLOUDS = ("aws", "azure", "gcp")
SEVERITIES = ("critical", "high", "medium", "low")
PG_TYPES = {"STRING": "text", "JSON": "jsonb", "BOOL": "boolean", "INT": "bigint",
            "DOUBLE": "double precision", "TIMESTAMP": "timestamptz",
            "IPADDR": "inet", "CIDR": "cidr", "LTREE": "text"}
STEAMPIPE_URL = "postgres://steampipe@localhost:9193/steampipe"


def psql(db, sql, read_only=True, schema=None):
    env = dict(os.environ)
    options = []
    if read_only:
        options.append("-c default_transaction_read_only=on")
    if schema:
        options.append(f"-c search_path={schema}")
    if options:
        env["PGOPTIONS"] = " ".join(options)
    done = subprocess.run(["psql", db, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-f", "-"],
                          input=sql, capture_output=True, text=True, env=env)
    if done.returncode:
        raise RuntimeError(done.stderr.strip() or "psql failed")
    return done.stdout.strip()


def query_rows(db, sql, schema=None):
    body = sql.strip().rstrip(";")
    out = psql(db, f"select coalesce(json_agg(q), '[]'::json) from (\n{body}\n) as q;", schema=schema)
    return json.loads(out)


def collect(db, out, clouds, schema=None, taken_at=None):
    """Write a snapshot. A failed query marks it incomplete; it is never silently treated as empty."""
    snapshot = {"taken_at": taken_at or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
                "clouds": list(clouds), "demo": schema == "ledger_demo",
                "inventory": [], "findings": [], "errors": []}
    for cloud in clouds:
        for kind in ("inventory", "findings"):
            path = ROOT / "queries" / kind / f"{cloud}.sql"
            try:
                rows = query_rows(db, path.read_text(), schema)
                snapshot[kind] += rows
                print(f"  {cloud:<5} {kind:<9} {len(rows):>5} rows")
            except RuntimeError as err:
                snapshot["errors"].append({"query": f"{kind}/{cloud}.sql", "error": str(err)})
                print(f"  {cloud:<5} {kind:<9} FAILED: {err}", file=sys.stderr)
    out = pathlib.Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(snapshot, indent=1) + "\n")
    return snapshot


def load_demo(db, day):
    schema = json.loads((ROOT / "tests" / "schema.json").read_text())
    data = json.loads((ROOT / "sample-data" / f"day{day}.json").read_text())
    sql = ["begin;", "drop schema if exists ledger_demo cascade;", "create schema ledger_demo;"]
    for table, columns in schema.items():
        if table.startswith("_"):
            continue
        cols = ", ".join(f'"{n}" {PG_TYPES[t]}' for n, t in columns.items())
        sql.append(f"create table ledger_demo.{table} ({cols});")
        rows = data.get(table, [])
        unknown = {k for row in rows for k in row} - set(columns)
        if unknown:
            raise SystemExit(f"{table}: sample data uses columns the plugin does not have: {sorted(unknown)}")
        if rows:
            payload = json.dumps(rows).replace("'", "''")
            sql.append(f"insert into ledger_demo.{table} select * from "
                       f"jsonb_populate_recordset(null::ledger_demo.{table}, '{payload}'::jsonb);")
    sql.append("commit;")
    psql(db, "\n".join(sql), read_only=False)
    print(f"loaded day {day} sample data into schema ledger_demo")


def key(finding):
    return tuple(finding[k] for k in ("control", "cloud", "account", "resource_id"))


def resource_key(row):
    return tuple(row[k] for k in ("cloud", "account", "category", "resource_id"))


def diff(old, new):
    """Compare two snapshots, only for clouds that both collected without errors."""
    def usable(snapshot):
        failed = {e["query"].split("/")[1].removesuffix(".sql") for e in snapshot["errors"]}
        return set(snapshot["clouds"]) - failed
    shared = usable(old) & usable(new)
    def pick(snapshot, kind, fn):
        return {fn(r): r for r in snapshot[kind] if r["cloud"] in shared}
    result = {"compared": sorted(shared), "skipped": sorted((set(old["clouds"]) | set(new["clouds"])) - shared)}
    for label, kind, fn in (("resources", "inventory", resource_key), ("findings", "findings", key)):
        a, b = pick(old, kind, fn), pick(new, kind, fn)
        result[f"new_{label}"] = [b[k] for k in sorted(b.keys() - a.keys())]
        result[f"gone_{label}"] = [a[k] for k in sorted(a.keys() - b.keys())]
    return result


def summarise(snapshot, controls, rates):
    findings = []
    for f in snapshot["findings"]:
        c = controls[f["control"]]
        monthly = None
        if f["control"] == "COST-01" and f.get("gb") is not None:
            monthly = round(f["gb"] * rates["disk_gb_month"], 2)
        elif f["control"] == "COST-02":
            monthly = rates["idle_ip_month"]
        findings.append({**f, "severity": c["severity"], "title": c["title"], "fix": c["fix"], "monthly": monthly})
    findings.sort(key=lambda f: (SEVERITIES.index(f["severity"]), f["control"], f["cloud"], f["resource_id"]))
    taggable = [r for r in snapshot["inventory"] if r["taggable"]]
    coverage = {field: {"tagged": sum(1 for r in taggable if r[field]), "total": len(taggable)}
                for field in ("owner", "cost_center", "environment")}
    return {
        "findings": findings,
        "severity": {s: sum(1 for f in findings if f["severity"] == s) for s in SEVERITIES},
        "matrix": {c: dict(collections.Counter(r["category"] for r in snapshot["inventory"] if r["cloud"] == c))
                   for c in snapshot["clouds"]},
        "coverage": coverage,
        "monthly_waste": round(sum(f["monthly"] or 0 for f in findings), 2),
    }


def mermaid_label(value):
    """Cloud names are untrusted: keep only characters that cannot change the diagram's structure."""
    return "".join(ch if ch.isalnum() or ch in " -_." else " " for ch in str(value))[:60]


def estate_diagram(snapshot, summary):
    """Mermaid map of cloud -> account -> resource counts, red where critical findings exist."""
    counts, critical = collections.Counter(), collections.Counter()
    for r in snapshot["inventory"]:
        counts[(r["cloud"], r["account"], r["category"])] += 1
    for f in summary["findings"]:
        if f["severity"] == "critical":
            critical[(f["cloud"], f["account"])] += 1
    lines = ["flowchart LR", '  org(["Estate"])']
    for ci, cloud in enumerate(snapshot["clouds"]):
        failed = any(e["query"].endswith(f"/{cloud}.sql") for e in snapshot["errors"])
        lines.append(f'  org --> c{ci}["{cloud.upper()}{" - COLLECTION FAILED" if failed else ""}"]')
        for ai, account in enumerate(sorted({k[1] for k in counts if k[0] == cloud})):
            node = f"c{ci}a{ai}"
            mix = "<br/>".join(f"{n} x {mermaid_label(cat)}" for (c, a, cat), n in sorted(counts.items())
                               if c == cloud and a == account)
            bad = critical[(cloud, account)]
            note = f"<br/><b>{bad} critical</b>" if bad else ""
            lines.append(f'  c{ci} --> {node}["<b>{mermaid_label(account)}</b><br/>{mix}{note}"]')
            if bad:
                lines.append(f"  class {node} bad")
    lines.append("  classDef bad fill:#fde8e6,stroke:#b42318,color:#5c110b,stroke-width:2px")
    return "\n".join(lines) + "\n"


def csv_safe(value):
    """Stop spreadsheet apps running cloud tag values as formulas."""
    if isinstance(value, str) and value.startswith(("=", "+", "-", "@", "\t", "\r")):
        return "'" + value
    return value


def md(value):
    return str(value).replace("|", "\\|").replace("\n", " ").replace("<", "&lt;")


def report(snapshot_path, out_dir, previous=None):
    snapshot = json.loads(pathlib.Path(snapshot_path).read_text())
    controls = json.loads((ROOT / "queries" / "controls.json").read_text())
    rates = json.loads((ROOT / "config" / "rates.json").read_text())
    s = summarise(snapshot, controls, rates)
    changes = diff(json.loads(pathlib.Path(previous).read_text()), snapshot) if previous else None
    out = pathlib.Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    fields = ["cloud", "account", "region", "category", "resource_id", "name", "size", "state",
              "owner", "cost_center", "environment", "source_table"]
    with open(out / "inventory.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fields, extrasaction="ignore")
        w.writeheader()
        w.writerows({k: csv_safe(v) for k, v in r.items()} for r in snapshot["inventory"])

    lines = ["# Multicloud inventory report", "", f"Snapshot: {snapshot['taken_at']}"]
    if snapshot["demo"]:
        lines.append("**FICTIONAL SAMPLE DATA**")
    if snapshot["errors"]:
        lines += ["", "> **INCOMPLETE SNAPSHOT.** Counts below are too low. Failed: "
                  + ", ".join(e["query"] for e in snapshot["errors"])]
    lines += ["", f"- Resources: {len(snapshot['inventory'])}",
              "- Findings: " + ", ".join(f"{n} {k}" for k, n in s["severity"].items()),
              f"- Estimated idle disk and IP spend: {rates['currency']} {s['monthly_waste']:,.2f} a month "
              "(placeholder rates from config/rates.json)"]
    for field, c in s["coverage"].items():
        pct = f"{int(100 * c['tagged'] / c['total'] + 0.5)}%" if c["total"] else "n/a"
        lines.append(f"- `{field}` tag coverage: {pct} ({c['tagged']} of {c['total']})")
    if changes:
        lines += ["", "## Since the previous snapshot", "",
                  f"Compared: {', '.join(changes['compared']) or 'nothing'}. "
                  f"Not compared: {', '.join(changes['skipped']) or 'none'}.", ""]
        for label, title in (("new_findings", "New finding"), ("gone_findings", "No longer reported"),
                             ("new_resources", "New resource"), ("gone_resources", "Removed resource")):
            for r in changes[label]:
                lines.append(f"- {title}: {r.get('control', r.get('category'))} {r['cloud']} {md(r['resource_id'])}")
    lines += ["", "## Findings", "", "| Severity | Control | Cloud | Account | Resource | Detail |",
              "|---|---|---|---|---|---|"]
    lines += ["| " + " | ".join(md(f[k]) for k in ("severity", "control", "cloud", "account", "resource_id", "detail")) + " |"
              for f in s["findings"]]
    (out / "report.md").write_text("\n".join(lines) + "\n")

    diagram = estate_diagram(snapshot, s)
    (out / "estate.mmd").write_text(diagram)
    note = "Fictional sample data.\n\n" if snapshot["demo"] else ""
    (out / "estate.md").write_text(f"# Estate map\n\n{note}```mermaid\n{diagram}```\n")

    payload = {"taken_at": snapshot["taken_at"], "demo": snapshot["demo"], "errors": snapshot["errors"],
               "clouds": snapshot["clouds"], "inventory": snapshot["inventory"], "changes": changes,
               "currency": rates["currency"], **s}
    # "<" is escaped so a hostile tag value cannot close the script element.
    blob = json.dumps(payload).replace("<", "\\u003c")
    template = (ROOT / "dashboard" / "template.html").read_text()
    (out / "dashboard.html").write_text(template.replace("/*__DATA__*/null", blob))
    print(f"wrote {out}/report.md, inventory.csv, dashboard.html, estate.md")
    return snapshot, s


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("collect")
    c.add_argument("--db", default=os.environ.get("LEDGER_DB", STEAMPIPE_URL))
    c.add_argument("--clouds", default="aws,azure,gcp")
    c.add_argument("--out", required=True)
    c.add_argument("--demo", action="store_true", help="read the ledger_demo schema")
    r = sub.add_parser("report")
    r.add_argument("snapshot")
    r.add_argument("--previous")
    r.add_argument("--out", default="out")
    r.add_argument("--fail-on", choices=SEVERITIES, help="exit 2 if a finding at or above this severity exists")
    d = sub.add_parser("load-demo")
    d.add_argument("--db", required=True)
    d.add_argument("--day", type=int, choices=(1, 2), default=1)
    a = p.parse_args(argv)

    if a.cmd == "load-demo":
        load_demo(a.db, a.day)
        return 0
    if a.cmd == "collect":
        clouds = [x.strip() for x in a.clouds.split(",") if x.strip()]
        if not clouds or set(clouds) - set(CLOUDS):
            p.error(f"--clouds must be a list drawn from {','.join(CLOUDS)}")
        snapshot = collect(a.db, a.out, clouds, schema="ledger_demo" if a.demo else None)
        return 1 if snapshot["errors"] else 0
    snapshot, s = report(a.snapshot, a.out, a.previous)
    if snapshot["errors"]:
        return 1
    if a.fail_on:
        limit = SEVERITIES.index(a.fail_on)
        if any(SEVERITIES.index(f["severity"]) <= limit for f in s["findings"]):
            return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, FileNotFoundError) as err:
        sys.exit(f"error: {err}")
