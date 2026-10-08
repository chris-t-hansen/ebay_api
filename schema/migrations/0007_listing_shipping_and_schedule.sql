-- 0007_listing_shipping_and_schedule.sql
-- listing_shipping holds listing-level shipping CONFIG. It deliberately has no
-- weight/dimension/ZIP columns: those belong to package_spec and inventory_location,
-- and repeating them per listing is the 3NF defect in the original SKILL.md sketch.
-- 1:1 with listing, CASCADE because a shipping block has no meaning without its listing.

CREATE TABLE IF NOT EXISTS listing_shipping (
  listing_shipping_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  listing_id            BIGINT UNSIGNED NOT NULL,
  shipping_option_type_code VARCHAR(20) NOT NULL DEFAULT 'SHIP_TO_HOME',
  shipping_method_id    BIGINT UNSIGNED     NULL,
  package_spec_id       BIGINT UNSIGNED     NULL,
  inventory_location_id BIGINT UNSIGNED     NULL COMMENT 'supplies the ship-from postal code',
  ship_to_country_code  CHAR(2)         NOT NULL DEFAULT 'US',
  handling_time_days    TINYINT UNSIGNED NOT NULL DEFAULT 3,
  shipping_price_amount DECIMAL(8,2)        NULL COMMENT 'flat charge; NULL when free shipping',
  free_shipping_flag    TINYINT(1)      NOT NULL DEFAULT 0,
  insurance_amount      DECIMAL(8,2)        NULL,
  importe_tax_bearing_code VARCHAR(20)      NULL COMMENT 'international only: SELLER or BUYER',
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_listing_shipping PRIMARY KEY (listing_shipping_id),
  CONSTRAINT uq_listing_shipping_listing UNIQUE (listing_id),
  KEY idx_listing_shipping_shipping_method_id (shipping_method_id),
  KEY idx_listing_shipping_package_spec_id (package_spec_id),
  KEY idx_listing_shipping_inventory_location_id (inventory_location_id),
  CONSTRAINT fk_listing_shipping_listing FOREIGN KEY (listing_id)
    REFERENCES listing (listing_id) ON DELETE CASCADE,
  CONSTRAINT fk_listing_shipping_method FOREIGN KEY (shipping_method_id)
    REFERENCES shipping_method (shipping_method_id) ON DELETE RESTRICT,
  CONSTRAINT fk_listing_shipping_package_spec FOREIGN KEY (package_spec_id)
    REFERENCES package_spec (package_spec_id) ON DELETE RESTRICT,
  CONSTRAINT fk_listing_shipping_location FOREIGN KEY (inventory_location_id)
    REFERENCES inventory_location (inventory_location_id) ON DELETE RESTRICT,
  CONSTRAINT chk_listing_shipping_option CHECK (shipping_option_type_code IN ('SHIP_TO_HOME','LOCAL_PICKUP','SHIP_TO_HOME_AND_PICKUP')),
  CONSTRAINT chk_listing_shipping_handling CHECK (handling_time_days >= 0 AND handling_time_days <= 30),
  CONSTRAINT chk_listing_shipping_free CHECK (
    free_shipping_flag = 0 OR shipping_price_amount IS NULL OR shipping_price_amount = 0),
  CONSTRAINT chk_listing_shipping_tax_bearer CHECK (
    importe_tax_bearing_code IS NULL OR importe_tax_bearing_code IN ('SELLER','BUYER'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS listing_schedule (
  listing_schedule_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  listing_id            BIGINT UNSIGNED NOT NULL,
  schedule_batch_code   VARCHAR(30)         NULL COMMENT 'e.g. W2026-41-A, so a relist batch can be queued together',
  sort_order            SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  scheduled_start_time_utc DATETIME(6)  NOT NULL,
  schedule_status_code  VARCHAR(20)     NOT NULL DEFAULT 'QUEUED',
  dry_run_flag          TINYINT(1)      NOT NULL DEFAULT 1 COMMENT 'SKILL.md mandate: no accidental live auction creation',
  attempt_count         SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  last_attempt_timestamp_utc DATETIME(6)    NULL,
  published_listing_ebay_item_id VARCHAR(20) NULL,
  schedule_error_text   VARCHAR(1000)       NULL,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_listing_schedule PRIMARY KEY (listing_schedule_id),
  KEY idx_listing_schedule_batch_order (schedule_batch_code, sort_order),
  KEY idx_listing_schedule_scheduled_start (scheduled_start_time_utc),
  KEY idx_listing_schedule_listing_id (listing_id),
  CONSTRAINT fk_listing_schedule_listing FOREIGN KEY (listing_id)
    REFERENCES listing (listing_id) ON DELETE CASCADE,
  CONSTRAINT chk_listing_schedule_status CHECK (schedule_status_code IN ('QUEUED','SUBMITTED','PUBLISHED','FAILED','CANCELED')),
  CONSTRAINT chk_listing_schedule_order CHECK (sort_order > 0),
  CONSTRAINT chk_listing_schedule_attempts CHECK (attempt_count >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
