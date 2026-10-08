-- 0006_listing.sql
-- listing = an offer/published eBay listing. inventory_item : listing is 1:many ON PURPOSE -
-- relisting an unsold hobby item creates a new row, so relist history and price-trend
-- analysis survive. listing_title/listing_description are deliberate published snapshots:
-- a later edit to the item text must not rewrite what was actually sold under.
-- Highest bid / bid count are NOT stored; they are derived from the bid table.

CREATE TABLE IF NOT EXISTS listing (
  listing_id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  inventory_item_id     BIGINT UNSIGNED NOT NULL,
  relist_sequence_number SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  ebay_marketplace_id   BIGINT UNSIGNED NOT NULL,
  inventory_location_id BIGINT UNSIGNED     NULL COMMENT 'required to publish through the Inventory API',
  listing_type_code     VARCHAR(20)    NOT NULL DEFAULT 'AUCTION',
  listing_status_code   VARCHAR(20)    NOT NULL DEFAULT 'DRAFT',
  listing_title         VARCHAR(200)   NOT NULL,
  listing_description   MEDIUMTEXT         NULL,
  auction_start_price_amount DECIMAL(10,2)  NULL,
  buy_it_now_price_amount DECIMAL(10,2)    NULL,
  reserve_price_amount  DECIMAL(10,2)      NULL,
  bid_increment_amount  DECIMAL(10,2)      NULL,
  currency_code         CHAR(3)        NOT NULL DEFAULT 'USD',
  duration_days         SMALLINT UNSIGNED  NULL,
  quantity_available    INT UNSIGNED   NOT NULL DEFAULT 1,
  quantity_sold         INT UNSIGNED   NOT NULL DEFAULT 0,
  view_count            INT UNSIGNED       NULL COMMENT 'reported by eBay, not derivable locally',
  watcher_count         INT UNSIGNED       NULL,
  ebay_item_id          VARCHAR(20)        NULL COMMENT 'populated only after a successful publish',
  payment_business_policy_id BIGINT UNSIGNED NULL COMMENT 'descriptor prefix because listing joins business_policy three times',
  fulfillment_business_policy_id BIGINT UNSIGNED NULL,
  return_business_policy_id BIGINT UNSIGNED NULL,
  scheduled_start_time_utc DATETIME(6)     NULL,
  start_time_utc        DATETIME(6)        NULL,
  end_time_utc          DATETIME(6)        NULL,
  actual_end_time_utc   DATETIME(6)        NULL,
  last_sync_timestamp_utc DATETIME(6)      NULL,
  created_by_user       VARCHAR(255)   NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)   NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_listing PRIMARY KEY (listing_id),
  CONSTRAINT uq_listing_item_relist UNIQUE (inventory_item_id, relist_sequence_number),
  CONSTRAINT uq_listing_ebay_item_id UNIQUE (ebay_item_id),
  KEY idx_listing_marketplace_id (ebay_marketplace_id),
  KEY idx_listing_location_id (inventory_location_id),
  KEY idx_listing_status_end (listing_status_code, end_time_utc),
  KEY idx_listing_payment_business_policy_id (payment_business_policy_id),
  KEY idx_listing_fulfillment_business_policy_id (fulfillment_business_policy_id),
  KEY idx_listing_return_business_policy_id (return_business_policy_id),
  FULLTEXT KEY ft_listing_title_description (listing_title, listing_description),
  CONSTRAINT fk_listing_inventory_item FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_item (inventory_item_id) ON DELETE RESTRICT,
  CONSTRAINT fk_listing_marketplace FOREIGN KEY (ebay_marketplace_id)
    REFERENCES ebay_marketplace (ebay_marketplace_id) ON DELETE RESTRICT,
  CONSTRAINT fk_listing_location FOREIGN KEY (inventory_location_id)
    REFERENCES inventory_location (inventory_location_id) ON DELETE RESTRICT,
  CONSTRAINT fk_listing_payment_policy FOREIGN KEY (payment_business_policy_id)
    REFERENCES business_policy (business_policy_id) ON DELETE RESTRICT,
  CONSTRAINT fk_listing_fulfillment_policy FOREIGN KEY (fulfillment_business_policy_id)
    REFERENCES business_policy (business_policy_id) ON DELETE RESTRICT,
  CONSTRAINT fk_listing_return_policy FOREIGN KEY (return_business_policy_id)
    REFERENCES business_policy (business_policy_id) ON DELETE RESTRICT,
  CONSTRAINT chk_listing_type CHECK (listing_type_code IN ('AUCTION','FIXED_PRICE','AUCTION_WITH_BIN')),
  CONSTRAINT chk_listing_status CHECK (listing_status_code IN ('DRAFT','SCHEDULED','ACTIVE','PAUSED','UNSOLD','SOLD','CANCELED')),
  CONSTRAINT chk_listing_relist_sequence CHECK (relist_sequence_number > 0),
  CONSTRAINT chk_listing_bin_over_start CHECK (
    buy_it_now_price_amount IS NULL OR auction_start_price_amount IS NULL
    OR buy_it_now_price_amount >= auction_start_price_amount),
  CONSTRAINT chk_listing_reserve_over_start CHECK (
    reserve_price_amount IS NULL OR auction_start_price_amount IS NULL
    OR reserve_price_amount >= auction_start_price_amount),
  CONSTRAINT chk_listing_prices_positive CHECK (
    (auction_start_price_amount IS NULL OR auction_start_price_amount >= 0)
    AND (buy_it_now_price_amount IS NULL OR buy_it_now_price_amount >= 0)
    AND (reserve_price_amount IS NULL OR reserve_price_amount >= 0)
    AND (bid_increment_amount IS NULL OR bid_increment_amount >= 0)),
  CONSTRAINT chk_listing_duration CHECK (duration_days IS NULL OR (duration_days >= 1 AND duration_days <= 90)),
  CONSTRAINT chk_listing_quantities CHECK (quantity_available >= 0 AND quantity_sold >= 0),
  CONSTRAINT chk_listing_time_window CHECK (
    start_time_utc IS NULL OR end_time_utc IS NULL OR end_time_utc > start_time_utc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
