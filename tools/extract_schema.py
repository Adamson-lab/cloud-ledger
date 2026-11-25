#!/usr/bin/env python3
"""Rebuild tests/schema.json from the official Steampipe plugin source.

Usage: python3 tools/extract_schema.py DIR
DIR holds clones of turbot/steampipe-plugin-{aws,azure,gcp}.
"""
import json, pathlib, re, subprocess, sys

TABLES = {
    "aws": ["aws_ec2_instance", "aws_ebs_volume", "aws_s3_bucket", "aws_rds_db_instance",
            "aws_vpc_security_group_rule", "aws_vpc_eip"],
    "azure": ["azure_compute_virtual_machine", "azure_compute_disk", "azure_storage_account",
              "azure_sql_server", "azure_network_security_group", "azure_public_ip"],
    "gcp": ["gcp_compute_instance", "gcp_compute_disk", "gcp_storage_bucket",
            "gcp_sql_database_instance", "gcp_compute_firewall", "gcp_compute_address"],
}
COLUMN = re.compile(r'Name:\s*"(\w+)"(?:(?!Name:\s*").)*?Type:\s*proto\.ColumnType_(\w+)', re.S)

def block(text, start):
    """Return the brace-balanced block that opens at or after `start`."""
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        depth += {"{": 1, "}": -1}.get(text[j], 0)
        if depth == 0:
            return text[i:j + 1]
    raise ValueError("unbalanced braces")

def functions(sources):
    out = {}
    for text in sources:
        for m in re.finditer(r"^func (\w+)\(", text, re.M):
            end = text.find("\n}\n", m.start())
            out[m.group(1)] = text[m.start():end]
    return out

def common(funcs, name, seen=()):
    """Columns added by a wrapper such as awsRegionalColumns, following nested calls."""
    body = funcs.get(name, "")
    cols = dict(COLUMN.findall(body))
    for called in re.findall(r"(\w*[Cc]olumns\w*)\(", body):
        if called != name and called not in seen:
            cols.update(common(funcs, called, (*seen, name)))
    return cols

def main(root):
    result = {}
    for plugin, tables in TABLES.items():
        repo = pathlib.Path(root) / f"steampipe-plugin-{plugin}"
        sources = [p.read_text() for p in sorted((repo / plugin).glob("*.go"))]
        funcs = functions(sources)
        commit = subprocess.check_output(["git", "-C", str(repo), "log", "-1", "--format=%h %cs"], text=True).strip()
        result.setdefault("_source", {})[plugin] = f"turbot/steampipe-plugin-{plugin} @ {commit}"
        for table in tables:
            # Anchor on the table definition itself: other files can mention the same name.
            definition = re.compile(rf'plugin\.Table\{{\s*Name:\s*"{table}",')
            text, at = next((t, d.start()) for t in sources if (d := definition.search(t)))
            m = re.compile(r"\bColumns:\s*(?:(\w+)\()?").search(text, at)
            if m is None:
                sys.exit(f"no column list found for {table}")
            cols = dict(COLUMN.findall(block(text, m.end())))
            if m.group(1):
                cols.update(common(funcs, m.group(1)))
            result[table] = cols
    out = pathlib.Path(__file__).resolve().parent.parent / "tests" / "schema.json"
    out.write_text(json.dumps(result, indent=1) + "\n")
    for t, c in result.items():
        if t != "_source":
            print(t, len(c))

if __name__ == "__main__":
    main(sys.argv[1])
