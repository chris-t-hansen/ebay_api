-- 0008_ebay_user_and_bid.sql
-- ebay_user is referenced three ways (bidder, buyer, message sender/recipients), so the
-- joining columns carry descriptors rather than repeating a bare username string in bid,
-- sale_order and customer_message.

CREATE TABLE IF NOT EXISTS ebay_user (
  ebay_user_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  username              VARCHAR(80)   NOT NULL COMMENT 'stored in an accent/case-insensitive collation, matching how eBay treats usernames',
  ebay_account_id       VARCHAR(20)        NULL COMMENT 'PII-guarded public account id returned by newer APIs',
  feedback_score_value  SMALLINT          NULL,
  buyer_profile_flag    TINYINT(1)        NOT NULL DEFAULT 1,
  seller_profile_flag   TINYINT(1)        NOT NULL DEFAULT 0,
  problem_buyer_flag    TINYINT(1)        NOT NULL DEFAULT 0 COMMENT 'your own judgement, never eBay-sourced',
  blocked_flag          TINYINT(1)        NOT NULL DEFAULT 0,
  first_seen_timestamp_utc DATETIME(6)    NULL,
  last_seen_timestamp_utc  DATETIME(6)    NULL,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_ebay_user PRIMARY KEY (ebay_user_id),
  CONSTRAINT uq_ebay_user_username UNIQUE (username),
  CONSTRAINT uq_ebay_user_account_id UNIQUE (ebay_account_id),
  CONSTRAINT chk_ebay_user_username CHECK (username REGEXP '^[A-Za-z0-9_-]{3,80}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS bid (
  bid_id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  listing_id            BIGINT UNSIGNED NOT NULL,
  ebay_bid_id           VARCHAR(20)        NULL,
  bidder_ebay_user_id   BIGINT UNSIGNED    NULL COMMENT 'NULL when eBay returns only an alias',
  bidder_alias          VARCHAR(50)     NOT NULL COMMENT 'e.g. a***b, which is all the auction detail views expose',
  bid_amount            DECIMAL(10,2)   NOT NULL,
  bid_currency_code     CHAR(3)         NOT NULL DEFAULT 'USD',
  bid_quantity_units    INT UNSIGNED    NOT NULL DEFAULT 1,
  bid_timestamp_utc     DATETIME(6)     NOT NULL,
  bid_status_code       VARCHAR(20)     NOT NULL DEFAULT 'ACTIVE',
  proxy_bid_flag        TINYINT(1)      NOT NULL DEFAULT 0,
  automatic_bid_flag    TINYINT(1)      NOT NULL DEFAULT 0,
  retraction_flag       TINYINT(1)      NOT NULL DEFAULT 0,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_bid PRIMARY KEY (bid_id),
  CONSTRAINT uq_bid_listing_ebay_bid UNIQUE (listing_id, ebay_bid_id),
  KEY idx_bid_bidder_ebay_user_id (bidder_ebay_user_id),
  KEY idx_bid_listing_amount_time (listing_id, bid_amount, bid_timestamp_utc),
  CONSTRAINT fk_bid_listing FOREIGN KEY (listing_id)
    REFERENCES listing (listing_id) ON DELETE CASCADE,
  CONSTRAINT fk_bid_bidder_user FOREIGN KEY (bidder_ebay_user_id)
    REFERENCES ebay_user (ebay_user_id) ON DELETE RESTRICT,
  CONSTRAINT chk_bid_amount CHECK (bid_amount >= 0),
  CONSTRAINT chk_bid_quantity CHECK (bid_quantity_units > 0),
  CONSTRAINT chk_bid_status CHECK (bid_status_code IN ('ACTIVE','OUTBID','WON','LOST','CANCELED','RETRACTED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
