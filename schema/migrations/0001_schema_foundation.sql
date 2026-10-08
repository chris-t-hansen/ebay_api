-- 0001_schema_foundation.sql
-- eBay Listings & Sales Tracker :: schema foundation (versioning, sync state, marketplaces)
-- Target: MariaDB 11.8.6 (validated). CHECK constraints are PARSED AND ENFORCED on this server.
-- Convention: singular table names, PK = <table>_id BIGINT UNSIGNED AUTO_INCREMENT,
--             four audit columns last, no JSON, no reserved words, DECIMAL for all quantities.

CREATE TABLE IF NOT EXISTS schema_migration (
  schema_migration_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  migration_version     VARCHAR(10)   NOT NULL COMMENT 'zero-padded sequence from the file name, e.g. 0001',
  migration_name        VARCHAR(100)  NOT NULL,
  migration_checksum    CHAR(64)      NOT NULL COMMENT 'sha256 of the migration file at apply time',
  migration_status_code VARCHAR(20)   NOT NULL DEFAULT 'APPLIED',
  created_by_user       VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_schema_migration PRIMARY KEY (schema_migration_id),
  CONSTRAINT uq_schema_migration_version UNIQUE (migration_version),
  CONSTRAINT chk_schema_migration_status CHECK (migration_status_code IN ('APPLIED','REVERTED','FAILED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS ebay_marketplace (
  ebay_marketplace_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  marketplace_code      VARCHAR(10)   NOT NULL COMMENT 'eBay API value, e.g. EBAY_US',
  marketplace_name      VARCHAR(60)   NOT NULL,
  ebay_site_id          VARCHAR(10)       NULL COMMENT 'legacy Trading API site id, e.g. 0',
  currency_code         CHAR(3)       NOT NULL DEFAULT 'USD',
  locale_code           VARCHAR(10)   NOT NULL DEFAULT 'en-US',
  environment_code      VARCHAR(10)   NOT NULL DEFAULT 'SANDBOX' COMMENT 'sandbox and production rows coexist; no second database needed',
  active_flag           TINYINT(1)    NOT NULL DEFAULT 1,
  created_by_user       VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_ebay_marketplace PRIMARY KEY (ebay_marketplace_id),
  CONSTRAINT uq_ebay_marketplace_code_env UNIQUE (marketplace_code, environment_code),
  CONSTRAINT chk_ebay_marketplace_env CHECK (environment_code IN ('SANDBOX','PRODUCTION')),
  CONSTRAINT chk_ebay_marketplace_locale CHECK (locale_code REGEXP '^[a-z]{2}(-[A-Za-z]{2})?$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS api_sync_state (
  api_sync_state_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sync_scope_code       VARCHAR(50)   NOT NULL COMMENT 'e.g. SALE_ORDERS, BID_HISTORY, SELL_MESSAGES, BUSINESS_POLICIES, SHIPMENT_TRACKING',
  ebay_marketplace_id   BIGINT UNSIGNED   NULL,
  sync_status_code      VARCHAR(20)   NOT NULL DEFAULT 'IDLE',
  last_sync_timestamp_utc DATETIME(6)     NULL,
  sync_cursor_value     VARCHAR(255)      NULL COMMENT 'opaque continuation token returned by the API call',
  sync_record_count     INT UNSIGNED      NULL COMMENT 'records written by the most recent successful sync',
  sync_error_text       VARCHAR(1000)     NULL,
  created_by_user       VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)  NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_api_sync_state PRIMARY KEY (api_sync_state_id),
  CONSTRAINT uq_api_sync_state_scope UNIQUE (sync_scope_code, ebay_marketplace_id),
  KEY idx_api_sync_state_marketplace_id (ebay_marketplace_id),
  CONSTRAINT fk_api_sync_state_marketplace FOREIGN KEY (ebay_marketplace_id)
    REFERENCES ebay_marketplace (ebay_marketplace_id) ON DELETE RESTRICT,
  CONSTRAINT chk_api_sync_state_status CHECK (sync_status_code IN ('IDLE','RUNNING','PARTIAL','FAILED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
