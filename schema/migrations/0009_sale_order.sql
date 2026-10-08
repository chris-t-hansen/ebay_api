-- 0009_sale_order.sql
-- Replaces the single flat `sales` table from SKILL.md. eBay checkout produces an ORDER that
-- contains N LINE ITEMS (Fulfillment API: "the line items in the order are grouped into one or
-- more packages"), so header and line detail cannot share a table without violating 3NF.
-- ship_to_* columns are intentional per-order snapshots, not references to ebay_user: the buyer
-- may ship to a gift address, and a past order must never re-render a changed address.

CREATE TABLE IF NOT EXISTS sale_order (
  sale_order_id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ebay_order_id         VARCHAR(37)     NOT NULL COMMENT 'format 28-11638-15523',
  ebay_marketplace_id   BIGINT UNSIGNED NOT NULL,
  buyer_ebay_user_id    BIGINT UNSIGNED     NULL,
  order_status_code     VARCHAR(20)     NOT NULL DEFAULT 'NEW',
  payment_status_code   VARCHAR(20)     NOT NULL DEFAULT 'NOT_PAID',
  fulfillment_status_code VARCHAR(20)   NOT NULL DEFAULT 'UNSHIPPED',
  order_create_timestamp_utc DATETIME(6)    NOT NULL,
  order_paid_timestamp_utc   DATETIME(6)    NULL,
  order_shipped_timestamp_utc DATETIME(6)   NULL,
  order_completed_timestamp_utc DATETIME(6) NULL,
  subtotal_amount       DECIMAL(10,2)       NULL,
  shipping_paid_amount  DECIMAL(10,2)       NULL COMMENT 'what the buyer paid for shipping',
  sales_tax_amount      DECIMAL(10,2)       NULL COMMENT 'eBay collects and remits as marketplace facilitator',
  discount_amount       DECIMAL(10,2)       NULL,
  total_amount          DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
  currency_code         CHAR(3)         NOT NULL DEFAULT 'USD',
  buyer_message_text    VARCHAR(1000)       NULL,
  ship_to_recipient_name VARCHAR(100)       NULL,
  ship_to_address_line1 VARCHAR(120)        NULL,
  ship_to_address_line2 VARCHAR(120)        NULL,
  ship_to_city_name     VARCHAR(60)         NULL,
  ship_to_state_province_code VARCHAR(20)   NULL,
  ship_to_postal_code   VARCHAR(16)         NULL,
  ship_to_country_code  CHAR(2)         NOT NULL DEFAULT 'US',
  ship_to_phone_number  VARCHAR(30)         NULL,
  last_sync_timestamp_utc DATETIME(6)       NULL,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_sale_order PRIMARY KEY (sale_order_id),
  CONSTRAINT uq_sale_order_ebay_order_id UNIQUE (ebay_order_id),
  KEY idx_sale_order_buyer_ebay_user_id (buyer_ebay_user_id),
  KEY idx_sale_order_marketplace_id (ebay_marketplace_id),
  KEY idx_sale_order_status_create (order_status_code, order_create_timestamp_utc),
  CONSTRAINT fk_sale_order_marketplace FOREIGN KEY (ebay_marketplace_id)
    REFERENCES ebay_marketplace (ebay_marketplace_id) ON DELETE RESTRICT,
  CONSTRAINT fk_sale_order_buyer_user FOREIGN KEY (buyer_ebay_user_id)
    REFERENCES ebay_user (ebay_user_id) ON DELETE RESTRICT,
  CONSTRAINT chk_sale_order_status CHECK (order_status_code IN ('NEW','INVOICE_PENDING','PAID','SHIPPED','COMPLETED','CANCELED','CLOSED')),
  CONSTRAINT chk_sale_order_payment CHECK (payment_status_code IN ('NOT_PAID','PAID','PENDING','REFUNDED','PARTIALLY_REFUNDED')),
  CONSTRAINT chk_sale_order_fulfillment CHECK (fulfillment_status_code IN ('UNSHIPPED','PARTIALLY_SHIPPED','SHIPPED','DELIVERED','CANCELED')),
  CONSTRAINT chk_sale_order_amounts CHECK (
    total_amount >= 0
    AND (subtotal_amount IS NULL OR subtotal_amount >= 0)
    AND (shipping_paid_amount IS NULL OR shipping_paid_amount >= 0)
    AND (sales_tax_amount IS NULL OR sales_tax_amount >= 0)
    AND (discount_amount IS NULL OR discount_amount >= 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
