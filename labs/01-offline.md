# Lab 1: Run the whole pipeline offline (about 15 minutes)

No cloud account or Steampipe needed. You need Python 3.10+, `psql`, and Docker or any scratch PostgreSQL.

```bash
make db-up          # PostgreSQL 16 in Docker
make demo           # load day 1, collect, load day 2, collect, report
```

Using your own scratch PostgreSQL? Pass `DB=postgres://...` to every `make` command. The loader drops and recreates only the `ledger_demo` schema.

**Checkpoint:** the last line is `wrote out/report.md, inventory.csv, dashboard.html, estate.md`. Open `out/dashboard.html`. You should see 34 resources and 8 critical findings. Under "Changes", one new public bucket appears and two findings are gone.

Set the connection once, then load day 1 again:

```bash
export DB=postgres://postgres:ledger@localhost:5544/postgres
python3 ledger.py load-demo --db $DB --day 1
```

## Exercise A: query the estate by hand

```bash
psql $DB -c "set search_path=ledger_demo" \
  -c "select group_id, from_port, to_port, cidr_ipv4, cidr_ipv6 from aws_vpc_security_group_rule where not is_egress order by group_id"
```

```text
     group_id     | from_port | to_port | cidr_ipv4  | cidr_ipv6
------------------+-----------+---------+------------+-----------
 sg-demo-internal |        22 |      22 | 10.0.0.0/8 |
 sg-demo-jump     |        22 |      22 | 0.0.0.0/0  |
 sg-demo-v6       |      3300 |    3400 |            | ::/0
 sg-demo-web      |       443 |     443 | 0.0.0.0/0  |
```

Before reading on, decide which of these four should be flagged. The answer is `sg-demo-jump` and `sg-demo-v6`. The IPv6 range hides both 3306 and 3389.

## Exercise B: break something and catch it

In `sample-data/day1.json`, find the `sg-demo-web` rule. Change both ports so it reads `"from_port": 20, "to_port": 25`. Then run:

```bash
python3 ledger.py load-demo --db $DB --day 1
python3 ledger.py collect --db $DB --demo --out snapshots/broken.json
python3 ledger.py report snapshots/broken.json --out out
grep sg-demo-web out/report.md
```

**Checkpoint:** you get a `NET-01` row saying `internet ingress to port(s) 22`. Undo your edit with `git checkout sample-data/day1.json`.

## Exercise C: use it as a pipeline gate

```bash
python3 ledger.py report snapshots/day2.json --fail-on critical --out out; echo $?
```

**Checkpoint:** prints `2`. Exit codes: `0` passed, `1` incomplete or error, `2` gate failed.
