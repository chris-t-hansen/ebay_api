# Schema

26 tables, created **programmatically** by ordered migrations (SKILL.md §2 mandate). This
directory is the authoritative table list; it supersedes the 7-table sketch in `SKILL.md` §2.

## Commands

```bash
python schema/apply_migrations.py --status     # what is pending, change nothing
python schema/apply_migrations.py --dry-run    # validate + report, change nothing
python schema/apply_migrations.py              # apply to DB_NAME from .env
python schema/apply_migrations.py --database qwen_playground   # validate into a scratch db

python tests/schema_rules_check.py --database ebay_api   # audit SKILL.md rules vs live schema
python tests/schema_smoke_test.py --database ebay_api    # functional constraint test, rolls back
```

Never edit an applied migration - the runner compares SHA-256 checksums and aborts if a applied
file changed. Add the next numbered file instead.

## Migrations

| File | Tables |
|---|---|
| 0001_schema_foundation | schema_migration, ebay_marketplace, api_sync_state |
| 0002_shipping_and_policy_reference | shipping_carrier, shipping_method, business_policy, inventory_location |
| 0003_item_reference | item_condition, storage_location, ebay_category |
| 0004_package_and_inventory_item | package_spec, inventory_item |
| 0005_inventory_item_children | inventory_item_photo, inventory_item_attribute |
| 0006_listing | listing |
| 0007_listing_shipping_and_schedule | listing_shipping, listing_schedule |
| 0008_ebay_user_and_bid | ebay_user, bid |
| 0009_sale_order | sale_order |
| 0010_sale_order_line_item | sale_order_line_item |
| 0011_sale_order_fee_and_refund | sale_order_fee, order_refund |
| 0012_shipment | shipment, shipment_line_item |
| 0013_customer_message | customer_message |
| 0014_seed_reference_data | marketplace, carrier, method, condition reference rows |

## Relationship map

```
ebay_marketplace ─┬─ ebay_category ─┐
                  ├─ business_policy ┤
                  └─ api_sync_state  │
storage_location ─┐                  ├─ inventory_item ─┬─ inventory_item_photo
package_spec ─────┤                  │                  └─ inventory_item_attribute
item_condition ───┘                  │
                                     └─ listing ─┬─ listing_shipping ─┬─ shipping_method ─ shipping_carrier
   sale_order ─┬─ sale_order_line_item ──────────┘                    └─ inventory_location
               │            │
               ├─ sale_order_fee       ├─ bid (bidder -> ebay_user)
               ├─ order_refund         └─ customer_message (sender/recipient -> ebay_user)
               └─ shipment ─ shipment_line_item
```

## Deliberate design decisions

- **No eBay ID is ever a primary key.** eBay order/item/policy IDs are strings (`28-11638-15523`),
  so each table has a `BIGINT UNSIGNED` surrogate key plus a `VARCHAR` UNIQUE external ID column.
  External IDs are nullable where the object may exist locally before it is published.
- **`inventory_item` : `listing` is 1:many** so relisting an unsold item keeps price/duration history
  (`relist_sequence_number`). `listing_title`/`listing_description` are published snapshots.
- **`sale_order` + `sale_order_line_item`** replace the flat `sales` table: an eBay order always has
  N line items, so one table would violate 3NF.
- **No label file in the database.** `shipment` stores `tracking_number` + `shipping_carrier_id`
  (+ `shipping_cost_amount`, `label_refund_deadline_timestamp_utc`, `label_refund_status_code`,
  `label_refund_amount`). The PDF stays in Google Drive; `shipping_carrier.tracking_url_template`
  rebuilds the carrier tracking URL on demand.
- **Weight and dimensions live in `package_spec`**, referenced by `inventory_item`,
  `listing_shipping` and `shipment`, so listed weight and billed weight never overwrite each other.
- **Ship-from ZIP lives in `inventory_location.postal_code`**, not on `listing_shipping` (repeating
  it per listing was the 3NF defect in the original sketch).
- **`highest bid` and `bid count` are not columns** - derived from `bid`, so they cannot go stale.
- **`api_sync_state`** is what makes incremental polling of bids, messages and orders possible.
- Sandbox and production coexist as two `ebay_marketplace` rows (`environment_code`), so no
  second database is required.

## Known follow-ups

- `item_condition.ebay_condition_id` is left NULL: conditionIds differ per category and must be
  confirmed against the Sell Metadata API before publishing offers.
- `business_policy` rows must be synced from the Account API to obtain real `ebay_policy_id` values
  (required by the Inventory API on every offer).
- A stray legacy `test` table remains in `ebay_api` (from `test_db_connection.py`) and does not
  follow the naming/audit standards; drop it when convenient.
