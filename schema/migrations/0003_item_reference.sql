-- 0003_item_reference.sql
-- Condition, physical storage, and eBay category reference rows.

CREATE TABLE IF NOT EXISTS item_condition (
  item_condition_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  condition_code        VARCHAR(20)  NOT NULL COMMENT 'NEW, LIKE_NEW, VERY_GOOD, GOOD, FAIR, FOR_PARTS',
  condition_name        VARCHAR(60)  NOT NULL,
  ebay_condition_id     VARCHAR(10)      NULL COMMENT 'eBay numeric conditionId, e.g. 1000 = New',
  severity_sequence_number SMALLINT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'orders NEW -> FOR_PARTS in reports',
  active_flag           TINYINT(1)   NOT NULL DEFAULT 1,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_item_condition PRIMARY KEY (item_condition_id),
  CONSTRAINT uq_item_condition_code UNIQUE (condition_code),
  KEY idx_item_condition_severity (severity_sequence_number),
  CONSTRAINT chk_item_condition_sequence CHECK (severity_sequence_number > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS storage_location (
  storage_location_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  storage_location_code VARCHAR(30)  NOT NULL COMMENT 'where the physical item sits, e.g. BIN-A3, SHELF-2B',
  storage_location_note VARCHAR(255)     NULL,
  active_flag           TINYINT(1)   NOT NULL DEFAULT 1,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_storage_location PRIMARY KEY (storage_location_id),
  CONSTRAINT uq_storage_location_code UNIQUE (storage_location_code),
  CONSTRAINT chk_storage_location_code CHECK (storage_location_code REGEXP '^[A-Z0-9][A-Z0-9 ._-]{1,29}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS ebay_category (
  ebay_category_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ebay_category_code    VARCHAR(20)  NOT NULL COMMENT 'eBay numeric category id held as a string',
  category_name         VARCHAR(200) NOT NULL,
  parent_ebay_category_id BIGINT UNSIGNED NULL COMMENT 'self reference; NULL for a root category',
  ebay_marketplace_id   BIGINT UNSIGNED NOT NULL,
  leaf_node_flag        TINYINT(1)   NOT NULL DEFAULT 1,
  last_sync_timestamp_utc DATETIME(6)    NULL,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_ebay_category PRIMARY KEY (ebay_category_id),
  CONSTRAINT uq_ebay_category_marketplace_code UNIQUE (ebay_marketplace_id, ebay_category_code),
  KEY idx_ebay_category_parent_id (parent_ebay_category_id),
  CONSTRAINT fk_ebay_category_parent FOREIGN KEY (parent_ebay_category_id)
    REFERENCES ebay_category (ebay_category_id) ON DELETE RESTRICT,
  CONSTRAINT fk_ebay_category_marketplace FOREIGN KEY (ebay_marketplace_id)
    REFERENCES ebay_marketplace (ebay_marketplace_id) ON DELETE RESTRICT,
  CONSTRAINT chk_ebay_category_code CHECK (ebay_category_code REGEXP '^[0-9]{1,20}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
