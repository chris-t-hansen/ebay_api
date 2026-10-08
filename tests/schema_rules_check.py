#!/usr/bin/env python3
"""Schema linter: asserts the rules written in SKILL.md against a live MariaDB database.

    python tests/schema_rules_check.py --database qwen_playground

Exits 0 when every rule passes, 1 when any rule is violated. Every assertion is read from the
server (information_schema), never from the .sql text, so drift between file and database
cannot hide a problem.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import mariadb
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
EXPECTED_SUFFIX = ["created_by_user", "created_timestamp", "last_update_user", "last_update_timestamp"]
BANNED_NAMES = {"condition", "order", "key", "interval", "cursor", "type", "row", "level", "repeat", "desc", "asc"}
FULLTEXT_EXPECTING = {
    "inventory_item": ("item_title", "item_description"),
    "listing": ("listing_title", "listing_description"),
    "customer_message": ("message_subject", "message_body"),
}


def rows(cursor, query, args=None):
    cursor.execute(query, args or ())
    return cursor.fetchall() if cursor.description else []


def check(connection) -> list[str]:
    problems: list[str] = []
    cursor = connection.cursor()
    db = connection.database

    tables = [r[0] for r in rows(cursor,
        "SELECT table_name FROM information_schema.tables WHERE table_schema=?"
        " AND table_type='BASE TABLE' ORDER BY table_name", (db,))]
    problems.append(f"INFO: {len(tables)} base tables in {db}")

    for table in tables:
        cols = rows(cursor,
            "SELECT column_name, column_type, is_nullable, column_default, extra, ordinal_position"
            " FROM information_schema.columns WHERE table_schema=? AND table_name=?"
            " ORDER BY ordinal_position", (db, table))
        names = [c[0] for c in cols]

        for name in [table] + names:
            if name != name.lower() or " " in name:
                problems.append(f"{table}.{name}: name is not lower_case_with_underscores")
            if name in BANNED_NAMES:
                problems.append(f"{table}.{name}: reserved word used as a name")

        pk = [p[0] for p in rows(cursor,
            "SELECT column_name FROM information_schema.key_column_usage"
            " WHERE table_schema=? AND table_name=? AND constraint_name='PRIMARY'", (db, table))]
        if pk != [f"{table}_id"]:
            problems.append(f"{table}: primary key is {pk}, expected ['{table}_id']")
        else:
            pk_col = next(c for c in cols if c[0] == pk[0])
            if not ("bigint" in pk_col[1] and "unsigned" in pk_col[1]) or "auto_increment" not in pk_col[4].lower():
                problems.append(f"{table}: surrogate key must be BIGINT UNSIGNED AUTO_INCREMENT,"
                                f" got {pk_col[1]} / {pk_col[4]}")

        if names[-4:] != EXPECTED_SUFFIX:
            problems.append(f"{table}: last four columns are {names[-4:]}, expected {EXPECTED_SUFFIX}")

        for name, col_type, _null, _default, _extra, _pos in cols:
            low = col_type.lower()
            if "json" in low:
                problems.append(f"{table}.{name}: JSON column is forbidden")
            if any(t in low for t in ("float", "double", "real")):
                problems.append(f"{table}.{name}: FLOAT/DOUBLE forbidden, use DECIMAL ({col_type})")
            if "amount" in name and "decimal" not in low:
                problems.append(f"{table}.{name}: amount column should be DECIMAL, got {col_type}")
            if ("amount" in name or "price" in name or "cost" in name) and "unsigned" in low:
                problems.append(f"{table}.{name}: money must be signed DECIMAL to allow refunds")
            if "_timestamp_utc" in name and "(6)" not in low:
                problems.append(f"{table}.{name}: API timestamps need microsecond precision DATETIME(6)")

        fks = rows(cursor,
            "SELECT k.referenced_table_name, k.column_name, r.delete_rule"
            " FROM information_schema.referential_constraints r"
            " JOIN information_schema.key_column_usage k"
            "   ON k.constraint_name=r.constraint_name AND k.constraint_schema=r.constraint_schema"
            " WHERE r.constraint_schema=? AND r.table_name=?", (db, table))
        indexed_first = {i[0] for i in rows(cursor,
            "SELECT DISTINCT column_name FROM information_schema.statistics"
            " WHERE table_schema=? AND table_name=? AND seq_in_index=1", (db, table))}
        for _ref_table, col, delete_rule in fks:
            if col not in indexed_first:
                problems.append(f"{table}.{col}: foreign key column is not indexed")
            if delete_rule == "NO ACTION":
                problems.append(f"{table}.{col}: ON DELETE not declared (server reports NO ACTION)")
            elif delete_rule not in ("CASCADE", "RESTRICT"):
                problems.append(f"{table}.{col}: ON DELETE {delete_rule} - only CASCADE/RESTRICT allowed")

        for name in names:
            if not (name.endswith("sort_order") or name.endswith("sequence_number")):
                continue
            # The rule targets per-parent ordering, so a composite index (parent key + order
            # column) is required only when the table has a foreign key to a parent table.
            if fks:
                composite = rows(cursor,
                    "SELECT COUNT(DISTINCT s.index_name) FROM information_schema.statistics s"
                    " WHERE s.table_schema=? AND s.table_name=? AND s.column_name=?"
                    "   AND s.index_name IN ("
                    "     SELECT s2.index_name FROM information_schema.statistics s2"
                    "     WHERE s2.table_schema=? AND s2.table_name=?"
                    "     GROUP BY s2.index_name HAVING COUNT(DISTINCT s2.column_name) > 1)",
                    (db, table, name, db, table))
                if composite[0][0] == 0:
                    problems.append(f"{table}.{name}: _order/_number column lacks a composite index")
            else:
                single = rows(cursor,
                    "SELECT COUNT(*) FROM information_schema.statistics"
                    " WHERE table_schema=? AND table_name=? AND column_name=?", (db, table, name))
                if single[0][0] == 0:
                    problems.append(f"{table}.{name}: ordering column is not indexed")

    for table, (title, desc) in FULLTEXT_EXPECTING.items():
        ft = rows(cursor,
            "SELECT DISTINCT index_name FROM information_schema.statistics"
            " WHERE table_schema=? AND table_name=? AND index_type='FULLTEXT'", (db, table))
        if not ft:
            problems.append(f"{table}: missing FULLTEXT index on ({title}, {desc})")

    total_checks = rows(cursor,
        "SELECT COUNT(DISTINCT constraint_name) FROM information_schema.check_constraints"
        " WHERE constraint_schema=?", (db,))[0][0]
    problems.append(f"INFO: {total_checks} CHECK constraints defined")
    covered = {t for (t,) in rows(cursor,
        "SELECT DISTINCT table_name FROM information_schema.check_constraints"
        " WHERE constraint_schema=? AND constraint_name NOT LIKE '%_not_null'", (db,))}
    for table in tables:
        if table not in covered:
            problems.append(f"{table}: no named CHECK constraint defined")

    collations = rows(cursor,
        "SELECT DISTINCT table_collation FROM information_schema.tables WHERE table_schema=?", (db,))
    if len(collations) != 1:
        problems.append(f"mixed collations present: {[c[0] for c in collations]}")
    cursor.close()
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit the live schema against SKILL.md rules")
    parser.add_argument("--database", default=None, help="override DB_NAME")
    args = parser.parse_args()
    load_dotenv(PROJECT_ROOT / ".env")
    connection = mariadb.connect(
        host=os.getenv("DB_HOST", "localhost"), port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER"), password=os.getenv("DB_PASSWORD"),
        database=args.database or os.getenv("DB_NAME", "ebay_api"))
    try:
        results = check(connection)
    finally:
        connection.close()
    violations = [line for line in results if not line.startswith("INFO:")]
    for line in results:
        print(line if line.startswith("INFO:") else f"VIOLATION: {line}")
    print(f"RESULT: {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())

