import { copyFileSync, existsSync } from 'node:fs';
import { backup, DatabaseSync } from 'node:sqlite';

const dataPath = '/data/probe.sqlite';
const backupPath = '/backups/probe.sqlite';
const restoredPath = '/data/restored.sqlite';
const action = process.argv[2];
const actions = new Set(['write', 'read', 'backup', 'restore-check']);

if (process.argv.length !== 3 || !actions.has(action)) {
  console.error('Usage: node probe.mjs write|read|backup|restore-check');
  process.exit(2);
}

function countRows(database) {
  return database.prepare('SELECT COUNT(*) AS count FROM probe_events').get().count;
}

async function main() {
  if (action === 'restore-check') {
    if (!existsSync(backupPath)) {
      throw new Error('Backup missing; run backup first');
    }

    copyFileSync(backupPath, restoredPath);
    const restored = new DatabaseSync(restoredPath);
    try {
      const result = restored.prepare('PRAGMA integrity_check').get().integrity_check;
      if (result !== 'ok') {
        throw new Error(`Restored database integrity check failed: ${result}`);
      }
      console.log(`Restored copy: ${countRows(restored)} rows; integrity_check=${result}`);
    } finally {
      restored.close();
    }
    return;
  }

  if ((action === 'read' || action === 'backup') && !existsSync(dataPath)) {
    throw new Error('Database missing; run write first');
  }

  const database = new DatabaseSync(dataPath);
  try {
    database.exec('PRAGMA journal_mode=WAL');
    database.exec(
      'CREATE TABLE IF NOT EXISTS probe_events ' +
        '(id INTEGER PRIMARY KEY, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)',
    );

    if (action === 'write') {
      database.prepare('INSERT INTO probe_events DEFAULT VALUES').run();
      console.log(`Persistent database: ${countRows(database)} rows`);
    } else if (action === 'read') {
      console.log(`Reopened database: ${countRows(database)} rows`);
    } else {
      await backup(database, backupPath);
      console.log(`Online backup: ${countRows(database)} rows`);
    }
  } finally {
    database.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
