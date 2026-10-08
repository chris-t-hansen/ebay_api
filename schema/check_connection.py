#!/usr/bin/env python3
"""Verify the MariaDB connection described by .env - without ever printing a secret.

    python schema/check_connection.py
    python schema/check_connection.py --database qwen_playground
    python schema/check_connection.py -v

Replaces the deleted test_db_connection.py. Use it right after rotating the DB password or
editing .env: it reports only non-sensitive facts (server version, current user, table and
migration counts) and exits non-zero when the connection or query fails. Per SKILL.md section 3,
no credential value is ever echoed, and nothing is written to the database.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import mariadb
from dotenv import load_dotenv

ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def load_env() -> dict[str, str]:
    load_dotenv(ENV_FILE)
    return {
        "user": os.getenv("DB_USER") or "",
        "password": os.getenv("DB_PASSWORD") or "",
        "host": os.getenv("DB_HOST", "localhost"),
        "port": int(os.getenv("DB_PORT", "3306")),
        "database": os.getenv("DB_NAME", "ebay_api"),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check the .env MariaDB connection safely")
    parser.add_argument("--database", help="override DB_NAME for this check only")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args(argv)

    cfg = load_env()
    if args.database:
        cfg["database"] = args.database
    if not cfg["user"] or not cfg["password"]:
        print(f"FAIL  DB_USER/DB_PASSWORD missing from {ENV_FILE.name}")
        return 1
    # Report only the presence and length of the password, never its value.
    print(f"config  : host={cfg['host']} port={cfg['port']} db={cfg['database']} "
          f"user={cfg['user']} password_chars={len(cfg['password'])}")

    try:
        connection = mariadb.connect(**cfg, autocommit=True)
    except mariadb.Error as error:
        print(f"FAIL  connect: {error.msg} (errno {error.errno})")
        print("      check DB_USER / DB_PASSWORD in .env, that the server is running, and grants")
        return 1
    try:
        with connection.cursor() as cursor:
            cursor.execute("SET NAMES utf8mb4")
            cursor.execute("SELECT VERSION(), CURRENT_USER(), DATABASE()")
            version, current_user, database = cursor.fetchone()
            print(f"OK    connected: server={version} as={current_user} database={database}")
            cursor.execute(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()"
                " AND table_type = 'BASE TABLE'")
            tables = cursor.fetchone()[0]
            cursor.execute(
                "SELECT COUNT(*) FROM information_schema.tables"
                " WHERE table_schema = DATABASE() AND table_name = 'schema_migration'")
            tracked = cursor.fetchone()[0] == 1
            print(f"state : {tables} base tables, schema_migration {'present' if tracked else 'absent'}")
            if tracked:
                cursor.execute("SELECT COUNT(*) FROM schema_migration")
                print(f"       {cursor.fetchone()[0]} migrations recorded as applied")
            if args.verbose:
                cursor.execute(
                    "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE()"
                    " AND table_type = 'BASE TABLE' ORDER BY table_name")
                names = [row[0] for row in cursor.fetchall()]
                print("       " + (", ".join(names) if names else "(no tables yet)"))
        return 0
    except mariadb.Error as error:
        print(f"FAIL  query: {error.msg} (errno {error.errno})")
        return 1
    finally:
        connection.close()


if __name__ == "__main__":
    sys.exit(main())
