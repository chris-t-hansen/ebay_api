-- 0004_package_and_inventory_item.sql
-- package_spec is shared by inventory_item, listing_shipping and shipment so that listed
-- weight/dimensions and the box actually billed are never forced into the same row.

CREATE TABLE IF NOT EXISTS package_spec (
  package_spec_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  package_name          VARCHAR(80)  NOT NULL COMMENT 'e.g. USPS Flat Rate Box Small, Media Mail Tube',
  package_type_code     VARCHAR(20)  NOT NULL DEFAULT 'BOX',
  dimension_unit_code   CHAR(2)      NOT NULL DEFAULT 'IN' COMMENT 'IN or CM',
  package_length_inches DECIMAL(6,2)     NULL,
  package_width_inches  DECIMAL(6,2)     NULL,
  package_height_inches DECIMAL(6,2)     NULL,
  package_weight_pounds SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'tare weight of the packaging',
  package_weight_ounces DECIMAL(6,2)     NOT NULL DEFAULT 0.00,
  package_weight_total_ounces DECIMAL(9,2) GENERATED ALWAYS AS (package_weight_pounds * 16 + package_weight_ounces) STORED
    COMMENT 'single sortable value for rate lookups',
  max_content_weight_ounces DECIMAL(9,2) NULL,
  reusable_flag         TINYINT(1)   NOT NULL DEFAULT 1,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_package_spec PRIMARY KEY (package_spec_id),
  CONSTRAINT uq_package_spec_name UNIQUE (package_name),
  KEY idx_package_spec_weight_total_ounces (package_weight_total_ounces),
  CONSTRAINT chk_package_spec_type CHECK (package_type_code IN ('BOX','BUBBLE_ENVELOPE','FLAT_ENVELOPE','TUBE','PADDED_BAG','ORIGINAL_PACKAGING','OTHER')),
  CONSTRAINT chk_package_spec_unit CHECK (dimension_unit_code IN ('IN','CM')),
  CONSTRAINT chk_package_spec_ounces CHECK (package_weight_ounces >= 0 AND package_weight_ounces < 16),
  CONSTRAINT chk_package_spec_dimensions CHECK (
    (package_length_inches IS NULL OR package_length_inches > 0)
    AND (package_width_inches IS NULL OR package_width_inches > 0)
    AND (package_height_inches IS NULL OR package_height_inches > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS inventory_item (
  inventory_item_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  seller_sku            VARCHAR(50)  NOT NULL COMMENT 'seller-assigned lot number; unique across eBay inventory',
  item_title            VARCHAR(200) NOT NULL,
  item_description      MEDIUMTEXT       NULL,
  item_condition_id     BIGINT UNSIGNED NOT NULL,
  ebay_category_id      BIGINT UNSIGNED  NULL COMMENT 'category name lives in ebay_category - caching it here would be transitive',
  storage_location_id   BIGINT UNSIGNED  NULL,
  package_spec_id       BIGINT UNSIGNED  NULL,
  unit_weight_pounds    SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'gross shipping weight of the packed item',
  unit_weight_ounces    DECIMAL(6,2)   NOT NULL DEFAULT 0.00,
  unit_weight_total_ounces DECIMAL(9,2) GENERATED ALWAYS AS (unit_weight_pounds * 16 + unit_weight_ounces) STORED,
  quantity_on_hand      INT UNSIGNED   NOT NULL DEFAULT 1 COMMENT 'hobby inventory is almost always one-of-a-kind',
  unique_item_flag      TINYINT(1)     NOT NULL DEFAULT 1,
  unit_cost_amount      DECIMAL(10,2)    NULL COMMENT 'what you paid for it; NULL when unknown',
  currency_code         CHAR(3)        NOT NULL DEFAULT 'USD',
  acquisition_source_note VARCHAR(255)   NULL,
  inventory_status_code VARCHAR(20)    NOT NULL DEFAULT 'ACTIVE',
  created_by_user       VARCHAR(255)   NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)   NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_inventory_item PRIMARY KEY (inventory_item_id),
  CONSTRAINT uq_inventory_item_sku UNIQUE (seller_sku),
  KEY idx_inventory_item_condition_id (item_condition_id),
  KEY idx_inventory_item_category_id (ebay_category_id),
  KEY idx_inventory_item_storage_location_id (storage_location_id),
  KEY idx_inventory_item_package_spec_id (package_spec_id),
  KEY idx_inventory_item_weight_total_ounces (unit_weight_total_ounces),
  FULLTEXT KEY ft_inventory_item_title_description (item_title, item_description),
  CONSTRAINT fk_inventory_item_condition FOREIGN KEY (item_condition_id)
    REFERENCES item_condition (item_condition_id) ON DELETE RESTRICT,
  CONSTRAINT fk_inventory_item_category FOREIGN KEY (ebay_category_id)
    REFERENCES ebay_category (ebay_category_id) ON DELETE RESTRICT,
  CONSTRAINT fk_inventory_item_storage_location FOREIGN KEY (storage_location_id)
    REFERENCES storage_location (storage_location_id) ON DELETE RESTRICT,
  CONSTRAINT fk_inventory_item_package_spec FOREIGN KEY (package_spec_id)
    REFERENCES package_spec (package_spec_id) ON DELETE RESTRICT,
  CONSTRAINT chk_inventory_item_sku CHECK (seller_sku REGEXP '^[A-Za-z0-9][A-Za-z0-9._-]{2,49}$'),
  CONSTRAINT chk_inventory_item_weight CHECK (unit_weight_ounces >= 0 AND unit_weight_ounces < 16),
  CONSTRAINT chk_inventory_item_quantity CHECK (quantity_on_hand >= 0),
  CONSTRAINT chk_inventory_item_cost CHECK (unit_cost_amount IS NULL OR unit_cost_amount >= 0),
  CONSTRAINT chk_inventory_item_status CHECK (inventory_status_code IN ('DRAFT','ACTIVE','LISTED','SOLD','RESERVED','RETIRED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
