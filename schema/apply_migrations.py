#!/usr/bin/env python3
"""Apply the ordered schema migrations in schema/migrations to MariaDB.

    python schema/apply_migrations.py              apply pending migrations
    python schema/apply_migrations.py --dry-run    validate and report, change nothing
    python schema/apply_migrations.py --status     show what is pending
    python schema/apply_migrations.py --database scratch_db   target another database

Driver: `mariadb` (MariaDB Connector/Python). SKILL.md mandates programmatic, versioned table
creation and a dry-run mode for every automated task.
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import mariadb
from dotenv import load_dotenv

MIGRATION_DIR = Path(__file__).resolve().parent / "migrations"
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
MIGRATION_LOCK = "ebay_api_schema_migration"
VERSION_RE = re.compile(r"^(?P<version>\d{4})_(?P<name>[a-z0-9_]+)\.sql$")
TABLE_DDL_RE = re.compile(r"CREATE TABLE IF NOT EXISTS\s+`?(\w+)`?", re.IGNORECASE)


@dataclass(frozen=True)
class Migration:
    version: str
    name: str
    path: Path
    sql: str
    checksum: str

    @property
    def label(self) -> str:
        return f"{self.version}_{self.name}"

    @property
    def tables(self) -> list[str]:
        return TABLE_DDL_RE.findall(self.sql)


def discover_migrations(directory: Path) -> list[Migration]:
    """Return migrations ordered by their zero-padded file-name version."""
    found: list[Migration] = []
    for entry in sorted(directory.glob("*.sql")):
        match = VERSION_RE.match(entry.name)
        if not match:
            raise ValueError(f"migration file name must be NNNN_snake_case.sql, got {entry.name!r}")
        sql = entry.read_text(encoding="utf-8")
        found.append(Migration(match.group("version"), match.group("name"), entry, sql,
                               hashlib.sha256(sql.encode("utf-8")).hexdigest()))
    if len({m.version for m in found}) != len(found):
        raise ValueError("Duplicate migration version numbers exist")
    return found


def split_statements(sql: str) -> list[str]:
    """Split a migration into statements, honouring quotes and -- / # / block comments."""
    statements: list[str] = []
    buffer: list[str] = []
    quote: str | None = None
    line_comment = block_comment = False
    index = 0
    length = len(sql)
    while index < length:
        char = sql[index]
        nxt = sql[index + 1] if index + 1 < length else ""
        if line_comment:
            if char == "\n":
                line_comment = False
                buffer.append(" ")
            index += 1
            continue
        if block_comment:
            if char == "*" and nxt == "/":
                block_comment = False
                index += 2
                continue
            index += 1
            continue
        if quote:
            buffer.append(char)
            if char == "\\" and nxt:
                buffer.append(nxt)
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if char in ("'", '"', "`"):
            quote = char
            buffer.append(char)
            index += 1
            continue
        if char == "-" and nxt == "-":
            line_comment = True
            index += 2
            continue
        if char == "#":
            line_comment = True
            index += 1
            continue
        if char == "/" and nxt == "*":
            block_comment = True
            index += 2
            continue
        if char == ";":
            statement = "".join(buffer).strip()
            if statement:
                statements.append(statement)
            buffer = []
            index += 1
            continue
        buffer.append(char)
        index += 1
    tail = "".join(buffer).strip()
    if tail:
        statements.append(tail)
    return statements


def connect(database: str | None) -> mariadb.Connection:
    """Open an autocommit connection using credentials from the project .env file.

    Note: mariadb 1.1.x accepts neither `charset` nor `characterset` as a connect kwarg (the 2.0
    release candidate silently ignored `charset`), so the client charset is set with SET NAMES,
    which works on every driver version. The server default is already utf8mb4.
    """
    load_dotenv(ENV_FILE)
    target = database or os.getenv("DB_NAME", "ebay_api")
    connection = mariadb.connect(
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "3306")),
        database=target,
        autocommit=True,
    )
    with connection.cursor() as cursor:
        cursor.execute("SET NAMES utf8mb4")
    return connection


def server_version(connection: mariadb.Connection) -> str:
    """mariadb exposes server_version as an integer such as 110806; render it readably."""
    raw = getattr(connection, "server_version", None)
    if isinstance(raw, int):
        return f"{raw // 10000}.{raw // 100 % 100}.{raw % 100}"
    with connection.cursor() as cursor:
        cursor.execute("SELECT VERSION()")
        return str(cursor.fetchone()[0])


# Mirrors migration 0001 so the bookkeeping table exists before its first row is written.
TRACKING_DDL = """
CREATE TABLE IF NOT EXISTS schema_migration (
  schema_migration_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  migration_version     VARCHAR(10)   NOT NULL,
  migration_name        VARCHAR(100)  NOT NULL,
  migration_checksum    CHAR(64)      NOT NULL,
  migration_status_code VARCHAR(20)   NOT NULL DEFAULT 'APPLIED',
  created_by_user       VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                        ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_schema_migration PRIMARY KEY (schema_migration_id),
  CONSTRAINT uq_schema_migration_version UNIQUE (migration_version),
  CONSTRAINT chk_schema_migration_status CHECK (migration_status_code IN ('APPLIED','REVERTED','FAILED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci
"""


def applied_migrations(connection) -> dict[str, str]:
    """Applied version -> checksum. Empty when the bookkeeping table does not exist yet,
    which is the normal state for --dry-run / --status against a fresh database."""
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT COUNT(*) FROM information_schema.tables"
            " WHERE table_schema = DATABASE() AND table_name = 'schema_migration'")
        if cursor.fetchone()[0] == 0:
            return {}
        cursor.execute("SELECT migration_version, migration_checksum FROM schema_migration")
        return {row[0]: row[1] for row in cursor.fetchall()}


def run_migration(connection, migration: Migration) -> None:
    statements = split_statements(migration.sql)
    with connection.cursor() as cursor:
        for statement in statements:
            cursor.execute(statement)
        cursor.execute(
            "INSERT INTO schema_migration (migration_version, migration_name, migration_checksum)"
            " VALUES (?, ?, ?)",
            (migration.version, migration.name, migration.checksum),
        )
    suffix = f", tables: {', '.join(migration.tables)}" if migration.tables else ""
    logging.info("applied  %s (%d statements%s)", migration.label, len(statements), suffix)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Apply or inspect eBay tracker schema migrations")
    parser.add_argument("--database", help="override DB_NAME, e.g. a scratch database for validation")
    parser.add_argument("--dry-run", action="store_true", help="report only; execute nothing")
    parser.add_argument("--status", action="store_true", help="list pending migrations and exit")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(levelname)-7s %(message)s")
    log = logging.getLogger("apply_migrations")

    try:
        migrations = discover_migrations(MIGRATION_DIR)
    except ValueError as error:
        log.error("%s", error)
        return 2
    log.info("Discovered %d migrations in %s", len(migrations), MIGRATION_DIR)

    try:
        connection = connect(args.database)
    except mariadb.Error as error:
        log.error("Connect failed: %s", error.msg)
        return 1
    try:
        # Advisory lock: two concurrent runs otherwise race and both apply the same migration
        # (observed as "Duplicate entry '0013' for key 'uq_schema_migration_version'").
        with connection.cursor() as cursor:
            cursor.execute("SELECT GET_LOCK(?, 10)", (MIGRATION_LOCK,))
            if cursor.fetchone()[0] != 1:
                log.error("Another migration run holds the lock; aborting")
                return 3
        log.info("Target database: %s (server %s)", connection.database, server_version(connection))
        read_only = args.dry_run or args.status
        if not read_only:
            with connection.cursor() as cursor:
                cursor.execute(TRACKING_DDL)
        already = applied_migrations(connection)

        for migration in migrations:
            if migration.version in already:
                if already[migration.version] != migration.checksum:
                    log.error("Migration %s was edited after it was applied. Add a new migration.",
                              migration.label)
                    return 2
                logging.debug("skip     %s (already applied)", migration.label)
                continue
            preview = len(split_statements(migration.sql))
            suffix = f", tables: {', '.join(migration.tables)}" if migration.tables else ""
            if read_only:
                log.info("pending  %s (%d statements%s)", migration.label, preview, suffix)
                continue
            run_migration(connection, migration)

        if read_only:
            log.info("%d applied, %d pending - database unchanged",
                     len(already), len(migrations) - len(already))
        else:
            log.info("Schema is current in %s", connection.database)
        return 0
    except mariadb.Error as error:
        log.error("%s (errno %s, sqlstate %s)", error.msg, error.errno, error.sqlstate)
        return 1
    finally:
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT RELEASE_LOCK(?)", (MIGRATION_LOCK,))
        except mariadb.Error:
            pass  # closing the session releases the advisory lock regardless
        connection.close()


if __name__ == "__main__":
    sys.exit(main())

