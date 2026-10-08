# QWEN.md - eBay API Automation & Tracker Project

Welcome to the eBay API Automation and Tracking workspace! This file serves as the foundational context, architectural layout, and development guidelines for all AI agents working on this project.

---

## 1. Project Overview & Objectives

This project aims to build Python scripts and modular applications that interface with the **eBay API** and store data locally in a **MariaDB** database.

### Core Objectives:
1. **Auction & Activity Tracking:** Track auctions, active bids, sales, customer questions, shipping statuses, and other real-time activities.
2. **Inventory & Listing Automation:** Automate the selling process by creating new auction listings, scheduling start times, and supplying necessary item details, photos, and descriptions.
3. **Shipping Information:** Automate shipping information by tracking item weight, package dimensions, and shipping types for the listing (USPS Priority, USPS Ground Advantage, USPS Media Mail, UPS, Fedex, etc) 
4. **Transition Path:** Initial phase focuses on robust **Python scripts** with command-line interfaces. The architecture must remain modular and clean to easily transition into a full GUI/Web application later.

---

## 2. Technology Stack & Database Setup

- **Language:** Python 3.x
- **Database:** MariaDB (localhost, database: `ebay_api`)
- **Main Dependencies (Recommended):**
  - `mariadb` (MariaDB Connector/Python) - **the only approved driver.** `mysql-connector-python`
    was removed on purpose; do not reintroduce it. Pinned to **stable 1.1.14**, built from source
    (needs `build-essential python3-dev cmake pkg-config libmariadb-dev libmariadb-dev-compat`).
    Three verified incompatibilities with mysql-connector, all already handled in this codebase:
      * `fetchall()` after INSERT/DDL raises `ProgrammingError` (no result set) instead of returning
        an empty list - guard on `cursor.description`;
      * paramstyle is **qmark (`?`)**, not `%s`;
      * `connect()` accepts **neither `charset=` nor `characterset=`** on 1.1.x - issue
        `SET NAMES utf8mb4` after connecting (the 2.0 release candidate silently ignored `charset=`).
  - `requests` or `ebaysdk` (for eBay API calls)
  - `python-dotenv` (for secure configuration loading)
  - `pytest` (for automated unit and integration testing)

### Database Integration & Migration:
- The `ebay_api` database is created **programmatically** by the migrations in `schema/migrations/`
  and applied with `python schema/apply_migrations.py` (supports `--dry-run` and `--status`).
  Never hand-create tables; never edit an applied migration (the runner compares SHA-256 checksums
  and refuses) - add the next numbered file instead. See `schema/README.md` for the full table list,
  relationship map and design rationale.
- **Mandate:** All database tables must be created programmatically. Developers/agents must write schema initialization scripts (or ORM migrations) to create, index, and version database tables. Every migration is recorded in `schema_migration`.
- **Schema (26 tables; supersedes the original 7-table sketch):**
  - Reference: `ebay_marketplace` (sandbox + production rows), `shipping_carrier`, `shipping_method`,
    `business_policy` (payment/fulfillment/return - eBay requires all three on an offer),
    `inventory_location` (supplies the ship-from ZIP), `item_condition`, `storage_location`,
    `package_spec` (weight/dimensions), `ebay_category`, `schema_migration`, `api_sync_state`
  - Inventory & listings: `inventory_item`, `inventory_item_photo`, `inventory_item_attribute`,
    `listing`, `listing_shipping`, `listing_schedule`
  - Activity: `ebay_user`, `bid`, `customer_message`
  - Sales & shipping: `sale_order`, `sale_order_line_item`, `sale_order_fee`, `order_refund`,
    `shipment`, `shipment_line_item`
  - Key modelling rules learned the hard way: no eBay identifier is ever a primary key (they are
    strings like `28-11638-15523`, so each table has a BIGINT surrogate plus a UNIQUE external-ID
    column); `sale_order` + `sale_order_line_item` replace a flat `sales` table because an order
    always holds N line items; weight/dimensions live in `package_spec`, not on each listing;
    photos and item specifics are child tables because JSON columns are forbidden; highest bid and
    bid count are derived from `bid`, never stored.
  - Shipping labels: the PDF is **not** stored in the database (it is printed immediately and
    backed up to Google Drive). `shipment` holds `tracking_number` + `shipping_carrier_id`, the
    dates, and the refund window (`shipping_cost_amount`, `label_refund_deadline_timestamp_utc`,
    `label_refund_status_code`, `label_refund_amount`). `shipping_carrier.tracking_url_template`
    rebuilds the carrier's tracking page URL from the number.

### Database Standards:
#### Table and Column creation

- Use lower case and underscores for all table and column names 
  - (i.e. recipe_name) - Primary key should be the name of the table with an underscore `_id` (i.e. `recipe_id`)
  - Every table should have the following four columns at the end (`created_by_user` varchar(255) NOT NULL DEFAULT CURRENT_USER(), `created_timestamp` timestamp NOT NULL DEFAULT current_timestamp(), `last_update_user` varchar(255) NOT NULL DEFAULT CURRENT_USER(), `last_update_timestamp` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) 
  - No JSON columns
  - Do not use database reserved keywords as table or column names. (ie: never name a column `type` or `procedure`. Always include a descriptive word like `item_type`)
    Verified against MariaDB 11.8.6 (a bare word fails to parse as a name): `condition`, `order`,
    `key`, `interval`, `cursor`. Verified safe: `status`, `content`, `description`, `location`,
    `message`, `body`, `subject`, `text`, `package`, `shipment`, `duration`, `tax`, `checksum`,
    `currency`, `refund`, `dispute`, `zone`. Note `condition` is fatal - always use a prefix such as
    `item_condition_code`. Syntax-only probing cannot validate everything: use
    `PREPARE`/`EXECUTE` for keyword checks, but only executing the DDL catches cross-table foreign
    keys, FULLTEXT creation and the AUTO_INCREMENT-in-CHECK ban.
  - Foreign keys should generally have the same name as the column they are referencing. The exception is where a table is joined multiple times and then a descriptor like `type1`, `type2`, `to`, `from` , etc may be added to the column name

#### Normalization & Constraints
  - All tables must be 3NF compliant
  - Use BIGINT UNSIGNED AUTO_INCREMENT for all surrogate keys
  - Define all FOREIGN KEY constraints with explicit ON DELETE (CASCADE for junction tables, RESTRICT for master tables with dependencies)
  - Add CHECK constraints. On the live server (**MariaDB 11.8.6**) they are **enforced**, not merely
    parsed - the old "parsed but not enforced before 10.2.3" caveat no longer applies here, so write
    CHECKs expecting them to reject bad data (verified: `chk_*` failures raise errno 4025).
    Two MariaDB limits found by executing the DDL, not by reading it:
      * a CHECK clause **may not reference an AUTO_INCREMENT column** (error 1901), so
        self-referential rules such as "a message cannot be its own reply" belong in application code;
      * CHECK with `REGEXP` works and is enforced, e.g. the tracking-number format guard.
  - Use DECIMAL for all quantities, never FLOAT/DOUBLE

#### Indexes
  - Index every foreign key column
  - FULLTEXT index on title and description columns
  - Composite index on _order columns (ie: table_id, sort_order) and _number columns (ie: table_id, step_number)

### Scratch validation database: `qwen_playground`

A second local database, `qwen_playground`, exists on this host and is **intentionally provided for
exactly this purpose** (confirmed by the owner): executing DDL and testing migrations so that
`ebay_api` is never used as a test bed. Future agents should treat it as the standard validation
target and should not create additional scratch databases.

Why it is necessary: the account `DB_USER` holds `ALL PRIVILEGES` on `ebay_api` and on
`qwen_playground`, but has **no global `CREATE` privilege**, so a temporary scratch database cannot
be created. Syntax-only probing (`PREPARE`) cannot verify foreign-key targets, FULLTEXT index
creation, generated columns or CHECK semantics - only executing the statements can, which is what
`qwen_playground` is for.

Standard workflow (the three commands below are the accepted way to validate any schema change):

```bash
python schema/apply_migrations.py --database qwen_playground   # execute the real DDL
python tests/schema_rules_check.py --database qwen_playground  # 0 violations expected
python tests/schema_smoke_test.py --database qwen_playground   # all checks pass, rolls back
```

Rules for using it:

- Always pass `--database qwen_playground`; the default target is `ebay_api`.
- **Restore it to empty when finished** - drop every table (`SET FOREIGN_KEY_CHECKS=0`, drop,
  re-enable) so the scratch database is left as found. It is a shared workspace, not a dumping ground.
- Never write real seller data, live credentials or eBay production rows into it.
- `--dry-run` / `--status` are safe against `ebay_api` because they execute nothing.
- Validation status as of the current schema: **26 tables, 65 CHECK constraints, 0 rule violations,
  19/19 smoke checks passing.**

---

## 3. Strict Security & Credential Guidelines (CRITICAL)

### **DO NOT store credentials in QWEN.md or any other tracked file.**
This includes MariaDB database usernames/passwords, eBay API client IDs, client secrets, developer tokens, or OAuth access keys.

### Never display secret files in tool output (hard rule for agents)
- Do **not** read, `cat`, or otherwise print `.env`, `.env.*`, or any file likely to hold live
  credentials. Anything shown in tool output becomes part of the agent conversation and is transmitted
  to the model provider, which is treated as disclosure.
- To compare or validate credentials, parse the file in a script and output only booleans, lengths, or
  key names - never values. Load them into a connection directly rather than echoing them.
- Do not copy secrets to `/tmp` or any scratch location, even as a "safety backup".
- Incident on 2026-10-07: an agent read `.env.template` together with project docs, which exposed the
  DB password and sandbox App/Cert IDs into the session transcript (and into `~/.cline/data/logs/`,
  `~/.cline/data/sessions/`, and `~/.qwen/.../chats/`). Remediation was to scrub `.env.template`,
  un-ignore it with `!.env.template`, and rotate the exposed credentials.

### Secure Configuration Pattern:
All configurations and secrets must be loaded from a `.env` file located in the project root. This file is excluded from version control via `.gitignore`.

#### Recommended `.env` Template:
Create a `.env.template` file with placeholder values to guide local development setup:

> **WARNING — do not copy `.env` into `.env.template`.** This file IS tracked and pushed to GitHub
> (`.gitignore` carries an explicit `!.env.template` exception). It must contain placeholders only —
> `replace_with_your_db_password`, `replace_with_your_ebay_app_id`, and so on. On 2026-10-07 the
> template was found to be byte-identical to `.env` with live credentials in it; it was untracked
> only by accident because the broader `.env.*` ignore rule matched it. Verify before committing:
> `git check-ignore -v .env.template` (should report the `!` exception) and confirm every secret line
> starts with `replace_with_`.

```ini
# MariaDB Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=ebay_api
DB_USER=your_agent_username
DB_PASSWORD=your_agent_password

# eBay API Credentials
EBAY_CLIENT_ID=your_client_id
EBAY_CLIENT_SECRET=your_client_secret
EBAY_RUNAME=your_ru_name
# sandbox or production
EBAY_ENV=sandbox
```

---

## 4. Development Workflow & Conventions
### A. Initial Architecture (Modular Python Scripts)
  - Separate database access code (e.g., DAOs, repositories) from eBay API integration code.
  - Implement robust logging and exception handling, especially around network requests to the eBay API and database queries.
  - Ensure all automated listing tasks support "Dry Runs" to prevent accidental costly API operations or active auction creation.

### B. Execution Lifecycle
1. **Research & Plan:** Before introducing new schema changes or API integrations, verify eBay API specifications and design the SQL schema.
2. **Surgical Implementation:** Apply clean, idiomatic Python code with type hints where applicable.
3. **Database & API Mocking:** Use test-driven approaches. Mock actual eBay API responses in tests to avoid hitting live sandbox or production endpoints during testing.

### C. Folder Structure Recommendation
```text
/home/qwen-dev/projects/ebay_api/
├── .gitignore
├── .env.template (template for credentials)
├── requirements.txt (Python dependencies)
├── schema/ (SQL migrations + the migration runner)
│   ├── apply_migrations.py  (--status / --dry-run / --database)
│   ├── check_connection.py  (validates .env without printing secrets)
│   └── migrations/NNNN_name.sql   (14 files, 26 tables, applied in order)
├── src/
│   ├── __init__.py
│   ├── config.py (loads environment variables)
│   ├── db/ (MariaDB connection and query execution)
│   ├── ebay_client/ (eBay API interaction)
│   └── tracking/ (auction tracking & listing logic)
└── tests/ (Unit and integration tests)
    ├── schema_rules_check.py  (audits the LIVE schema against the rules above)
    └── schema_smoke_test.py   (inserts a real chain, asserts CHECKs/FKs, rolls back)
```

---

## 5. eBay API Strategy (decided: full automation)

The owner's workflow is: enter every item into `inventory_item`, schedule a start date, have the app
publish the listing, then pull listings/sales/tracking back into the database. Both auctions and
Buy-It-Now are required, and labels are bought in Seller Hub (only tracking number + carrier are
stored).

### Chosen integration per job

| Job | API | Status |
|---|---|---|
| Inventory records (SKU, title, description, condition, specifics, photos) | Sell **Inventory API** (`createOrReplaceInventoryItem`) | verified endpoint list |
| Draft listing config, then publish | Sell **Inventory API** (`createOffer` → `publishOffer`) | verified |
| **Scheduled future start** | Sell **Inventory API** offer field `listingStartDate` | **verified**: "the seller can set a time in the future that the listing will become active, instead of the listing becoming active immediately after a publishOffer call". Maps to `listing.scheduled_start_time_utc` / `listing_schedule`. Note eBay's own caveat: scheduled listings "do not always start at the exact date/time specified". |
| **Dry run before spending money** | `POST /offer/get_listing_fees` + `startListingPreviewsCreation` | verified endpoints; use with `listing_schedule.dry_run_flag` before any publish |
| Business policies (payment / fulfillment / return) | Sell **Account API v1** | verified required: "Every offer must also reference a payment, a fulfillment, and a return business policy" |
| Orders, line items, shipment + tracking sync | Sell **Fulfillment API** (`getOrders`, `GET /order/{orderId}/shipping_fulfillment` returns `trackingNumber`, `shippingCarrierCode`, `shippedTime`, `estimatedDeliveryTime`) | verified; this is the free path for tracking, no Limited Release needed |
| **Bidder / bid history on own auctions** | Legacy **Trading API** (`GetBidders` / `GetItem` bidding data) | **NOT verified** - the Inventory API endpoint list has no bid retrieval, so a second API is almost certainly needed here |
| Label purchase | **Not via API.** eBay's Logistics/eDelivery APIs are restricted (Limited Release) | buy in Seller Hub, then sync tracking from Fulfillment API; cost/refund columns may need manual entry |

### Open items that block `src/ebay_client/`

1. **Auction with Buy-It-Now combined on one listing** is unconfirmed for the Inventory API. Its offer
   model exposes `format` (auction or fixed price), `listing_duration` and `pricing_summary`, but no
   visible buy-it-now price field, and the docs note that an expired auction "becomes available as a
   fixed-price offer and will be GTC". Confirm on sandbox before writing the publish path. Fallback
   that already fits the schema: list auction and fixed-price as separate `listing` rows, or relist
   unsold auctions as GTC fixed-price (the `relist_sequence_number` history is designed for this).
2. **Confirm the bid-source call** (Trading `GetBidders`) and its required scope; the `bid` table
   already accepts an alias-only bidder (`bidder_alias` NOT NULL, `bidder_ebay_user_id` nullable).
3. **Account prerequisites (owner action, not agent action):** eBay Developers Program account with
   an App ID/Cert ID/RuName (present in `.env`, sandbox), the seller account **opted in to business
   policies**, Advanced API access approved for the sell scopes, and OAuth user consent obtained.
   Until then `business_policy.ebay_policy_id` cannot be populated and no offer can be published.
4. `item_condition.ebay_condition_id` is intentionally NULL - conditionIds are category-specific and
   must be read from the Sell Metadata API before publishing.

### Column-level mapping notes

- `listing.ebay_offer_id` stores the Inventory API `offerId` (needed to update/withdraw/publish);
  `listing.ebay_item_id` is filled only after publishing. Both are UNIQUE and nullable, so a draft
  row is legal.
- `listing.listing_duration_code` stores eBay's enum (`Days_7`, `GTC`, ...) while `duration_days`
  stays as the human/CLI-friendly number; the column's case-insensitive collation means the CHECK
  accepts `Days_7` or `DAYS_7` equally.
- `inventory_location.location_code` is the Inventory API `merchantBusinessLocationId`.
- `inventory_item.seller_sku` is the Inventory API `sku` (must be unique across the seller's
  inventory, max 50 chars - matching the CHECK).

