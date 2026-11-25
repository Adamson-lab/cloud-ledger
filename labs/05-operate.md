# Lab 5: Run it every day

1. Put the runner on a locked-down host inside your network. Keep port 9193 on localhost.
2. Use short-lived credentials: an instance role, managed identity or workload identity federation. Do not store keys.
3. Schedule it, for example with cron:

   ```cron
   0 5 * * * cd /opt/cloud-ledger && LEDGER_DB="$(cat /etc/cloud-ledger/db-url)" ./scripts/snapshot.sh >> /var/log/cloud-ledger.log 2>&1
   ```

   Protect `/etc/cloud-ledger/db-url` with file permissions, because it contains a password.
4. Alert on a non-zero exit. A failed collection matters as much as a new finding.
5. Treat `snapshots/` and `out/` as confidential. They map your weak points. Encrypt them, restrict access, set a retention period, and never commit them to Git or publish them to a public page.

## Weekly review

| Question | Where to look |
|---|---|
| What became exposed? | New findings, critical first |
| What appeared that nobody claims? | New resources with no owner |
| Can we trust the numbers? | Incomplete snapshots, then a spot check against the consoles |
| Is ownership improving? | Tag coverage over time |
