-- 0010_sale_order_line_item.sql
-- One row per eBay transaction (line item) inside an order.

CREATE TABLE IF NOT EXISTS sale_order_line_item (
  sale_order_line_item_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sale_order_id         BIGINT UNSIGNED NOT NULL,
  line_item_sequence_number SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  ebay_transaction_id   VARCHAR(37)         NULL,
  listing_id            BIGINT UNSIGNED     NULL COMMENT 'RESTRICT: sales history must survive listing cleanup',
  inventory_item_id     BIGINT UNSIGNED NOT NULL,
  seller_sku_snapshot   VARCHAR(50)     NOT NULL COMMENT 'SKU as it read at purchase time',
  line_item_quantity_units INT UNSIGNED NOT NULL DEFAULT 1,
  transaction_price_amount DECIMAL(10,2) NOT NULL COMMENT 'unit price actually paid',
  tax_amount            DECIMAL(10,2)       NULL,
  eb_credit_amount      DECIMAL(10,2)       NULL,
  condition_snapshot_code VARCHAR(20)       NULL,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_sale_order_line_item PRIMARY KEY (sale_order_line_item_id),
  CONSTRAINT uq_sale_order_line_transaction UNIQUE (sale_order_id, ebay_transaction_id),
  CONSTRAINT uq_sale_order_line_sequence UNIQUE (sale_order_id, line_item_sequence_number),
  KEY idx_sale_order_line_item_listing_id (listing_id),
  KEY idx_sale_order_line_item_inventory_item_id (inventory_item_id),
  CONSTRAINT fk_sale_order_line_item_order FOREIGN KEY (sale_order_id)
    REFERENCES sale_order (sale_order_id) ON DELETE CASCADE,
  CONSTRAINT fk_sale_order_line_item_listing FOREIGN KEY (listing_id)
    REFERENCES listing (listing_id) ON DELETE RESTRICT,
  CONSTRAINT fk_sale_order_line_item_inventory_item FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_item (inventory_item_id) ON DELETE RESTRICT,
  CONSTRAINT chk_sale_order_line_quantity CHECK (line_item_quantity_units > 0),
  CONSTRAINT chk_sale_order_line_price CHECK (
    transaction_price_amount >= 0
    AND (tax_amount IS NULL OR tax_amount >= 0)
    AND (eb_credit_amount IS NULL OR eb_credit_amount >= 0)),
  CONSTRAINT chk_sale_order_line_sequence CHECK (line_item_sequence_number > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
