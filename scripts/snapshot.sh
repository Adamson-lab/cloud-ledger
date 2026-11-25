#!/usr/bin/env bash
# Collect from a running Steampipe service, compare with the last complete snapshot, report.
# Set LEDGER_DB to the connection string printed by: steampipe service start --show-password
set -euo pipefail
cd "$(dirname "$0")/.."
: "${LEDGER_DB:?set LEDGER_DB to your Steampipe connection string}"
mkdir -p snapshots/live
previous=$(find snapshots/live -name '*.json' ! -name '*.incomplete.json' | sort | tail -n 1)
now="snapshots/live/$(date -u +%Y%m%dT%H%M%SZ).json"
status=0
python3 ledger.py collect --db "$LEDGER_DB" --clouds "${LEDGER_CLOUDS:-aws,azure,gcp}" --out "$now" || status=$?
if [ "$status" -ne 0 ]; then
  [ -f "$now" ] || exit "$status"
  mv "$now" "${now%.json}.incomplete.json"
  now="${now%.json}.incomplete.json"
fi
python3 ledger.py report "$now" ${previous:+--previous "$previous"} --out out
