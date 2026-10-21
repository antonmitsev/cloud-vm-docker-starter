"""One-off SQLite persistence and backup probe for the local Compose simulation."""

import shutil
import sqlite3
import sys
from pathlib import Path


DATA = Path("/data/probe.sqlite")
BACKUP = Path("/backups/probe.sqlite")
RESTORED = Path("/data/restored.sqlite")


def count(connection: sqlite3.Connection) -> int:
    return connection.execute("SELECT COUNT(*) FROM probe_events").fetchone()[0]


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in {
        "write", "read", "backup", "restore-check"
    }:
        raise SystemExit("Usage: probe.py write|read|backup|restore-check")

    action = sys.argv[1]
    if action == "restore-check":
        if not BACKUP.is_file():
            raise SystemExit("Backup missing; run backup first")
        shutil.copy2(BACKUP, RESTORED)
        with sqlite3.connect(RESTORED) as restored:
            result = restored.execute("PRAGMA integrity_check").fetchone()[0]
            if result != "ok":
                raise SystemExit(f"Restored database integrity check failed: {result}")
            print(f"Restored copy: {count(restored)} rows; integrity_check={result}")
        return

    if action == "read" and not DATA.is_file():
        raise SystemExit("Database missing; run write first")
    if action == "backup" and not DATA.is_file():
        raise SystemExit("Database missing; run write first")

    with sqlite3.connect(DATA) as database:
        database.execute("PRAGMA journal_mode=WAL")
        database.execute(
            "CREATE TABLE IF NOT EXISTS probe_events "
            "(id INTEGER PRIMARY KEY, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)"
        )
        if action == "write":
            database.execute("INSERT INTO probe_events DEFAULT VALUES")
            database.commit()
            print(f"Persistent database: {count(database)} rows")
        elif action == "read":
            print(f"Reopened database: {count(database)} rows")
        else:
            with sqlite3.connect(BACKUP) as destination:
                database.backup(destination)
            print(f"Online backup: {count(database)} rows")


if __name__ == "__main__":
    main()
