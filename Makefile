# Offline demo database. Override DB to use any scratch PostgreSQL.
DB ?= postgres://postgres:ledger@localhost:5544/postgres

.PHONY: db-up db-down demo test live
db-up:
	docker run -d --name ledger-demo-db -e POSTGRES_PASSWORD=ledger -p 127.0.0.1:5544:5432 postgres:16
	until docker exec ledger-demo-db pg_isready -U postgres -h 127.0.0.1; do sleep 1; done
db-down:
	docker rm -f ledger-demo-db
demo:
	python3 ledger.py load-demo --db "$(DB)" --day 1
	python3 ledger.py collect --db "$(DB)" --demo --out snapshots/day1.json
	python3 ledger.py load-demo --db "$(DB)" --day 2
	python3 ledger.py collect --db "$(DB)" --demo --out snapshots/day2.json
	python3 ledger.py report snapshots/day2.json --previous snapshots/day1.json --out out
test:
	LEDGER_TEST_DB="$(DB)" python3 -m unittest discover -s tests -v
live:
	./scripts/snapshot.sh
