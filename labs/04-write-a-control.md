# Lab 4: Write your own control

Goal: `DB-03`, an RDS instance with automated backups turned off.

**1. Add sample data.** In `sample-data/day1.json`, add `"backup_retention_period": 0,` to the `reporting-poc` database row.

**2. Prove the query alone.**

```bash
python3 ledger.py load-demo --db $DB --day 1
psql $DB -c "set search_path=ledger_demo" -c "select 'DB-03' as control, db_instance_identifier, backup_retention_period from aws_rds_db_instance where backup_retention_period = 0"
```

**Checkpoint:** one row, `reporting-poc`.

**3. Add it to the pack.** In `queries/findings/aws.sql`, insert this above the final `order by`:

```sql
union all
select 'DB-03', 'aws', account_id, region, db_instance_identifier,
       'automated backups are turned off', null
from aws_rds_db_instance
where backup_retention_period = 0
```

**4. Describe it** in `queries/controls.json` (add a comma after the previous entry):

```json
"DB-03": {"severity": "high", "title": "Database backups turned off", "fix": "Set a retention period that meets your recovery policy."}
```

**5. Lock it in.** Add `("DB-03", "reporting-poc")` to `EXPECTED_DAY1` in `tests/test_ledger.py`, then run `make test DB=$DB`.

**Checkpoint:** all tests pass.

To use a table that is not in `tests/schema.json`, add its name to `tools/extract_schema.py`, clone the plugin repositories into one folder, and run `python3 tools/extract_schema.py <folder>`.
