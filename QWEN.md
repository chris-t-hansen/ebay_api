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
  - `mariadb` (from pip for MariaDB interface)
  - `requests` or `ebaysdk` (for eBay API calls)
  - `python-dotenv` (for secure configuration loading)
  - `pytest` (for automated unit and integration testing)

### Database Integration & Migration:
- The `ebay_api` database is currently empty.
- **Mandate:** All database tables must be created programmatically. Developers/agents must write schema initialization scripts (or ORM migrations) to create, index, and version database tables.
- **Schema Focus:**
  - `inventory` (items, description, price, status, photos)
  - `listings` (ebay_item_id, start_time, end_time, price, status)
  - `bids` (bidder, amount, timestamp)
  - `sales` (transaction_id, buyer, item, shipping_status)
  - `customer_messages` (message_id, sender, content, responded_status)
  - `shipping_method` (shipping_method_id, shipping_method_name, vendor)
  - `listing_shipping` (listing_shipping_id, weight_pounds, weight_ounces, package_height, package_length, package_width, mailing_from_zip_code)

### Database Standards:
#### Table and Column creation

- Use lower case and underscores for all table and column names 
  - (i.e. recipe_name) - Primary key should be the name of the table with an underscore `_id` (i.e. `recipe_id`)
  - Every table should have the following four columns at the end (`created_by_user` varchar(255) NOT NULL DEFAULT CURRENT_USER(), `created_timestamp` timestamp NOT NULL DEFAULT current_timestamp(), `last_update_user` varchar(255) NOT NULL DEFAULT CURRENT_USER(), `last_update_timestamp` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) 
  - No JSON columns
  - Do not use database reserved keywords as table or column names. (ie: never name a column `type` or `procedure`. Always include a descriptive word like `item_type`)
  - Foreign keys should generally have the same name as the column they are referencing. The exception is where a table is joined multiple times and then a descriptor like `type1`, `type2`, `to`, `from` , etc may be added to the column name

#### Normalization & Constraints
  - All tables must be 3NF compliant
  - Use BIGINT UNSIGNED AUTO_INCREMENT for all surrogate keys
  - Define all FOREIGN KEY constraints with explicit ON DELETE (CASCADE for junction tables, RESTRICT for master tables with dependencies)
  - Add CHECK constraints where MariaDB supports them (note: MariaDB 10.2.3+ supports CHECK, but they are parsed even if not enforced pre-10.2.3 — specify this caveat)
  - Use DECIMAL for all quantities, never FLOAT/DOUBLE

#### Indexes
  - Index every foreign key column
  - FULLTEXT index on title and description columns
  - Composite index on _order columns (ie: table_id, sort_order) and _number columns (ie: table_id, step_number)

---

## 3. Strict Security & Credential Guidelines (CRITICAL)

### **DO NOT store credentials in QWEN.md or any other tracked file.**
This includes MariaDB database usernames/passwords, eBay API client IDs, client secrets, developer tokens, or OAuth access keys. 

### Secure Configuration Pattern:
All configurations and secrets must be loaded from a `.env` file located in the project root. This file is excluded from version control via `.gitignore`.

#### Recommended `.env` Template:
Create a `.env.template` file with placeholder values to guide local development setup:

```ini
# MariaDB Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=ebay
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
├── schema/ (SQL initialization and migration scripts)
│   └── init_db.sql
├── src/
│   ├── __init__.py
│   ├── config.py (loads environment variables)
│   ├── db/ (MariaDB connection and query execution)
│   ├── ebay_client/ (eBay API interaction)
│   └── tracking/ (auction tracking & listing logic)
└── tests/ (Unit and integration tests)
```
