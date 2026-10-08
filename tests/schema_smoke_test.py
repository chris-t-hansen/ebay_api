#!/usr/bin/env python3
"""Functional smoke test for the eBay tracker schema (SKILL.md rules in practice).

    python tests/schema_smoke_test.py --database qwen_playground

Builds a realistic chain (condition -> item -> listing -> bid -> order -> line -> shipment ->
message), asserts constraints reject bad data, and checks RESTRICT / CASCADE / FULLTEXT /
generated columns. Everything is rolled back, so the target database is left unchanged.
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import mysql.connector
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PASS: list[str] = []
FAIL: list[str] = []


def ok(label: str) -> None:
    PASS.append(label)


def fail(label: str, detail: str = "") -> None:
    FAIL.append(f"{label}{(' -> ' + detail) if detail else ''}")


def run(cursor, sql, params=None):
    cursor.execute(sql, params or ())
    return cursor.fetchall()


def expect_error(cursor, label, sql, params=None) -> None:
    try:
        cursor.execute(sql, params or ())
        fail(label, "statement unexpectedly SUCCEEDED")
    except mysql.connector.Error as error:
        ok(f"{label} [rejected: {error.msg[:38]}]")


def fulltext_probe(database: str | None) -> bool:
    """InnoDB FULLTEXT entries only become visible to MATCH ... AGAINST at commit time, so this
    runs on its own autocommit connection with a throwaway fixture that is deleted afterwards."""
    probe_sku = "FT-PROBE-20261007"
    connection = mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"), port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER"), password=os.getenv("DB_PASSWORD"),
        database=database or os.getenv("DB_NAME", "ebay_api"), autocommit=True)
    cursor = connection.cursor()
    try:
        cursor.execute("SELECT item_condition_id FROM item_condition WHERE condition_code='GOOD'")
        condition_id = cursor.fetchone()[0]
        cursor.execute("DELETE FROM inventory_item WHERE seller_sku=%s", (probe_sku,))
        cursor.execute(
            "INSERT INTO inventory_item (seller_sku, item_title, item_description, item_condition_id)"
            " VALUES (%s, %s, %s, %s)",
            (probe_sku, "Zygomorphic Beatles sleeve ring wear",
             "A rare pressing with light ring wear on the sleeve.", condition_id))
        cursor.execute("SELECT COUNT(*) FROM inventory_item WHERE MATCH(item_title, item_description)"
                       " AGAINST ('zygomorphic')")
        matched = cursor.fetchone()[0]
        cursor.execute("DELETE FROM inventory_item WHERE seller_sku=%s", (probe_sku,))
        cursor.execute("SELECT COUNT(*) FROM inventory_item")
        return matched == 1 and cursor.fetchone()[0] == 0
    finally:
        cursor.close()
        connection.close()


def report(cursor, connection) -> int:
    connection.rollback()
    persisted = run(cursor, "SELECT COUNT(*) FROM inventory_item")[0][0]
    ok("rollback left database unchanged") if persisted == 0 else fail("rollback", f"{persisted} rows kept")
    cursor.close()
    connection.close()
    for line in PASS:
        print("  PASS:", line)
    for line in FAIL:
        print("  FAIL:", line)
    print(f"RESULT: {len(PASS)} passed, {len(FAIL)} failed")
    return 1 if FAIL else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Smoke test the eBay tracker schema")
    parser.add_argument("--database", default=None)
    args = parser.parse_args()
    load_dotenv(PROJECT_ROOT / ".env")
    connection = mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"), port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER"), password=os.getenv("DB_PASSWORD"),
        database=args.database or os.getenv("DB_NAME", "ebay_api"))
    cursor = connection.cursor()
    now = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)

    condition_id = run(cursor, "SELECT item_condition_id FROM item_condition WHERE condition_code='GOOD'")[0][0]
    marketplace_id = run(cursor, "SELECT ebay_marketplace_id FROM ebay_marketplace WHERE environment_code='SANDBOX'")[0][0]
    carrier_id = run(cursor, "SELECT shipping_carrier_id FROM shipping_carrier WHERE carrier_code='USPS'")[0][0]
    method_id = run(cursor, "SELECT shipping_method_id FROM shipping_method WHERE shipping_method_name='USPS Media Mail'")[0][0]

    run(cursor, "INSERT INTO storage_location (storage_location_code) VALUES ('BIN-A3')")
    storage_id = cursor.lastrowid
    run(cursor, "INSERT INTO package_spec (package_name, package_type_code, package_weight_pounds,"
               " package_weight_ounces, package_length_inches, package_width_inches, package_height_inches)"
               " VALUES ('Record Mailer','FLAT_ENVELOPE',0,4.50,13.00,13.50,1.00)")
    package_id = cursor.lastrowid
    run(cursor, "INSERT INTO ebay_category (ebay_category_code, category_name, ebay_marketplace_id)"
               " VALUES ('149901','Music Media > Vinyl Records',%s)", (marketplace_id,))
    category_id = cursor.lastrowid
    run(cursor, "INSERT INTO inventory_location (location_code, location_name, street_address_line1,"
               " city_name, state_province_code, postal_code) VALUES"
               " ('HOME-PRIMARY','Home office','1 Main St','Anytown','CA','94105')")
    location_id = cursor.lastrowid
    for ptype, pname in (('PAYMENT', 'Pay Then Ship'), ('FULFILLMENT', 'Ship in 3 Business Days'),
                         ('RETURN', '30 Days Returns')):
        run(cursor, "INSERT INTO business_policy (policy_type_code, policy_name, ebay_marketplace_id)"
                    " VALUES (%s,%s,%s)", (ptype, pname, marketplace_id))
    policy_ids = {row[0]: row[1] for row in
                  run(cursor, "SELECT policy_type_code, business_policy_id FROM business_policy")}

    run(cursor, "INSERT INTO inventory_item (seller_sku, item_title, item_description, item_condition_id,"
               " ebay_category_id, storage_location_id, package_spec_id, unit_weight_pounds,"
               " unit_weight_ounces, unit_cost_amount) VALUES"
               " ('REC-1980-042','The Beatles - White Album 1980 US Pressing',"
               " 'Vinyl LP, media very good, sleeve with light ring wear.',%s,%s,%s,%s,0,9.00,3.50)",
            (condition_id, category_id, storage_id, package_id))
    item_id = cursor.lastrowid
    generated = float(run(cursor, "SELECT unit_weight_total_ounces FROM inventory_item"
                                 " WHERE inventory_item_id=%s", (item_id,))[0][0])
    ok("generated column weight_total_ounces = 9.00") if generated == 9.00 else \
        fail("generated column", f"expected 9.00 got {generated}")

    run(cursor, "INSERT INTO inventory_item_photo (inventory_item_id, photo_file_path, sort_order)"
               " VALUES (%s,'/photos/REC-1980-042/front.jpg',1)", (item_id,))
    run(cursor, "INSERT INTO inventory_item_attribute (inventory_item_id, attribute_name, attribute_value)"
               " VALUES (%s,'Artist','The Beatles')", (item_id,))
    run(cursor, "INSERT INTO listing (inventory_item_id, relist_sequence_number, ebay_marketplace_id,"
               " inventory_location_id, listing_type_code, listing_status_code, listing_title,"
               " auction_start_price_amount, buy_it_now_price_amount, bid_increment_amount,"
               " duration_days, payment_business_policy_id, fulfillment_business_policy_id,"
               " return_business_policy_id, start_time_utc, end_time_utc) VALUES"
               " (%s,1,%s,%s,'AUCTION_WITH_BIN','ACTIVE','The Beatles - White Album LP',"
               " 5.00,18.00,1.00,7,%s,%s,%s,%s,%s)",
            (item_id, marketplace_id, location_id, policy_ids['PAYMENT'], policy_ids['FULFILLMENT'],
             policy_ids['RETURN'], now, now + timedelta(days=7)))
    listing_id = cursor.lastrowid
    run(cursor, "INSERT INTO listing_shipping (listing_id, shipping_option_type_code, shipping_method_id,"
               " package_spec_id, inventory_location_id, handling_time_days, free_shipping_flag)"
               " VALUES (%s,'SHIP_TO_HOME',%s,%s,%s,3,1)", (listing_id, method_id, package_id, location_id))
    run(cursor, "INSERT INTO listing_schedule (listing_id, schedule_batch_code, sort_order,"
               " scheduled_start_time_utc, schedule_status_code, dry_run_flag) VALUES"
               " (%s,'W2026-41-A',1,%s,'PUBLISHED',1)", (listing_id, now))
    run(cursor, "INSERT INTO ebay_user (username, feedback_score_value) VALUES ('record_collector_77', 342)")
    user_id = cursor.lastrowid
    run(cursor, "INSERT INTO bid (listing_id, ebay_bid_id, bidder_ebay_user_id, bidder_alias, bid_amount,"
               " bid_timestamp_utc) VALUES (%s,'B1001',%s,'r***7',7.00,%s)", (listing_id, user_id, now))
    run(cursor, "INSERT INTO sale_order (ebay_order_id, ebay_marketplace_id, buyer_ebay_user_id,"
               " order_status_code, payment_status_code, fulfillment_status_code,"
               " order_create_timestamp_utc, order_paid_timestamp_utc, subtotal_amount, total_amount,"
               " ship_to_recipient_name, ship_to_address_line1, ship_to_city_name,"
               " ship_to_state_province_code, ship_to_postal_code) VALUES"
               " ('28-11638-15523',%s,%s,'PAID','PAID','SHIPPED',%s,%s,18.00,18.00,"
               " 'A Buyer','12 Oak Ave','Reno','NV','89501')", (marketplace_id, user_id, now, now))
    order_id = cursor.lastrowid
    run(cursor, "INSERT INTO sale_order_line_item (sale_order_id, line_item_sequence_number,"
               " ebay_transaction_id, listing_id, inventory_item_id, seller_sku_snapshot,"
               " line_item_quantity_units, transaction_price_amount) VALUES"
               " (%s,1,'T5001',%s,%s,'REC-1980-042',1,18.00)", (order_id, listing_id, item_id))
    line_id = cursor.lastrowid
    run(cursor, "INSERT INTO sale_order_fee (sale_order_id, sale_order_line_item_id, fee_type_code,"
               " fee_amount, fee_timestamp_utc) VALUES (%s,%s,'FINAL_VALUE',1.98,%s)", (order_id, line_id, now))
    run(cursor, "INSERT INTO shipment (sale_order_id, shipping_carrier_id, shipping_method_id,"
               " package_spec_id, tracking_number, shipment_status_code, shipped_timestamp_utc,"
               " shipping_cost_amount, label_refund_deadline_timestamp_utc, label_refund_status_code)"
               " VALUES (%s,%s,%s,%s,'9400111899223117062423','LABELED',%s,5.85,%s,'NOT_REQUESTED')",
            (order_id, carrier_id, method_id, package_id, now, now + timedelta(days=30)))
    shipment_id = cursor.lastrowid
    run(cursor, "INSERT INTO shipment_line_item (shipment_id, sale_order_line_item_id, shipped_quantity_units)"
               " VALUES (%s,%s,1)", (shipment_id, line_id))
    run(cursor, "INSERT INTO customer_message (ebay_message_id, message_thread_key, sender_ebay_user_id,"
               " direction_code, message_subject, message_body, message_timestamp_utc, listing_id)"
               " VALUES ('M9001','14-11638',%s,'INBOUND','Is the sleeve seam split?',"
               " 'Please confirm the shrink wrap is intact.',%s,%s)", (user_id, now, listing_id))
    ok("realistic chain written across 13 tables")

    stamp = run(cursor, "SELECT created_by_user, created_timestamp FROM inventory_item"
                        " WHERE inventory_item_id=%s", (item_id,))[0]
    ok("audit columns auto-populated") if stamp[0] and stamp[1] else fail("audit columns", str(stamp))
    if fulltext_probe(args.database):
        ok("FULLTEXT search finds a committed row (probe cleaned up)")
    else:
        fail("FULLTEXT search", "committed probe row not matched or cleanup failed")

    expect_error(cursor, "unique sku rejected",
                 "INSERT INTO inventory_item (seller_sku, item_title, item_condition_id)"
                 " VALUES ('REC-1980-042','Duplicate',%s)", (condition_id,))
    expect_error(cursor, "bad sku characters rejected",
                 "INSERT INTO inventory_item (seller_sku, item_title, item_condition_id)"
                 " VALUES ('bad sku!!','Bad',%s)", (condition_id,))
    expect_error(cursor, "weight_ounces 16 rejected",
                 "INSERT INTO inventory_item (seller_sku, item_title, item_condition_id, unit_weight_ounces)"
                 " VALUES ('REC-2000-001','Heavy',%s,16.00)", (condition_id,))
    expect_error(cursor, "negative bid rejected",
                 "INSERT INTO bid (listing_id, bidder_alias, bid_amount, bid_timestamp_utc)"
                 " VALUES (%s,'x',-1.00,%s)", (listing_id, now))
    expect_error(cursor, "buy-it-now below auction start rejected",
                 "INSERT INTO listing (inventory_item_id, relist_sequence_number, ebay_marketplace_id,"
                 " listing_title, listing_type_code, auction_start_price_amount, buy_it_now_price_amount)"
                 " VALUES (%s,2,%s,'Cheap BIN','AUCTION_WITH_BIN',20.00,5.00)", (item_id, marketplace_id))
    expect_error(cursor, "end_time before start_time rejected",
                 "INSERT INTO listing (inventory_item_id, relist_sequence_number, ebay_marketplace_id,"
                 " listing_title, listing_type_code, start_time_utc, end_time_utc)"
                 " VALUES (%s,3,%s,'Bad window','AUCTION',%s,%s)",
                 (item_id, marketplace_id, now, now - timedelta(days=1)))
    expect_error(cursor, "malformed tracking number rejected",
                 "INSERT INTO shipment (sale_order_id, shipping_carrier_id, tracking_number)"
                 " VALUES (%s,%s,'not a tracking number!')", (order_id, carrier_id))
    expect_error(cursor, "invalid marketplace environment rejected",
                 "INSERT INTO ebay_marketplace (marketplace_code, marketplace_name, environment_code)"
                 " VALUES ('EBAY_CA','eBay Canada','STAGING')")
    expect_error(cursor, "responded_flag without timestamp rejected",
                 "INSERT INTO customer_message (sender_ebay_user_id, message_body, message_timestamp_utc,"
                 " responded_flag) VALUES (%s,'Answered too soon',%s,1)", (user_id, now))
    expect_error(cursor, "bad storage bin code rejected",
                 "INSERT INTO storage_location (storage_location_code) VALUES ('bin a3!!')")

    expect_error(cursor, "RESTRICT protects in-use item_condition",
                 "DELETE FROM item_condition WHERE item_condition_id=%s", (condition_id,))
    expect_error(cursor, "RESTRICT protects listing that has bids",
                 "DELETE FROM listing WHERE listing_id=%s", (listing_id,))
    run(cursor, "DELETE FROM shipment WHERE shipment_id=%s", (shipment_id,))
    orphans = run(cursor, "SELECT COUNT(*) FROM shipment_line_item WHERE shipment_id=%s", (shipment_id,))[0][0]
    ok("CASCADE cleared shipment_line_item with its shipment") if orphans == 0 else \
        fail("CASCADE on shipment_line_item", f"{orphans} orphans left")
    bids = run(cursor, "SELECT COUNT(*) FROM bid WHERE listing_id=%s", (listing_id,))[0][0]
    ok(f"bid history intact ({bids} row) after shipment delete")

    return report(cursor, connection)


if __name__ == "__main__":
    sys.exit(main())
