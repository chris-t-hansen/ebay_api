-- 0011_sale_order_fee_and_refund.sql
-- Fees are a child table because one order can carry several fee kinds; collapsing them into
-- columns would either hard-code a list eBay keeps changing or force a JSON column (forbidden).

CREATE TABLE IF NOT EXISTS sale_order_fee (
  sale_order_fee_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sale_order_id         BIGINT UNSIGNED NOT NULL,
  sale_order_line_item_id BIGINT UNSIGNED NULL COMMENT 'NULL for order-level fees such as subscription credits',
  fee_type_code         VARCHAR(30)     NOT NULL,
  fee_amount            DECIMAL(10,2)   NOT NULL COMMENT 'positive number that eBay charged you',
  fee_currency_code     CHAR(3)         NOT NULL DEFAULT 'USD',
  ebay_fund_transaction_id VARCHAR(37)      NULL,
  fee_timestamp_utc     DATETIME(6)         NULL,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_sale_order_fee PRIMARY KEY (sale_order_fee_id),
  CONSTRAINT uq_sale_order_fee_fund_transaction UNIQUE (sale_order_id, ebay_fund_transaction_id),
  KEY idx_sale_order_fee_line_item_id (sale_order_line_item_id),
  KEY idx_sale_order_fee_type (fee_type_code, fee_timestamp_utc),
  CONSTRAINT fk_sale_order_fee_order FOREIGN KEY (sale_order_id)
    REFERENCES sale_order (sale_order_id) ON DELETE CASCADE,
  CONSTRAINT fk_sale_order_fee_line_item FOREIGN KEY (sale_order_line_item_id)
    REFERENCES sale_order_line_item (sale_order_line_item_id) ON DELETE CASCADE,
  CONSTRAINT chk_sale_order_fee_amount CHECK (fee_amount >= 0),
  CONSTRAINT chk_sale_order_fee_type CHECK (
    fee_type_code IN ('FINAL_VALUE','INSERTION','ADVERTISING','LABEL','CARTON','PAYOUT','OTHER'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS order_refund (
  order_refund_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sale_order_id         BIGINT UNSIGNED NOT NULL,
  ebay_refund_id        VARCHAR(37)         NULL,
  refund_amount         DECIMAL(10,2)   NOT NULL,
  refund_currency_code  CHAR(3)         NOT NULL DEFAULT 'USD',
  refund_reason_code    VARCHAR(40)         NULL,
  refund_status_code    VARCHAR(20)     NOT NULL DEFAULT 'REQUESTED',
  return_requested_flag TINYINT(1)      NOT NULL DEFAULT 0,
  refund_create_timestamp_utc DATETIME(6)   NULL,
  refund_completed_timestamp_utc DATETIME(6) NULL,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_order_refund PRIMARY KEY (order_refund_id),
  CONSTRAINT uq_order_refund_ebay_id UNIQUE (ebay_refund_id),
  KEY idx_order_refund_order_status (sale_order_id, refund_status_code),
  CONSTRAINT fk_order_refund_order FOREIGN KEY (sale_order_id)
    REFERENCES sale_order (sale_order_id) ON DELETE CASCADE,
  CONSTRAINT chk_order_refund_amount CHECK (refund_amount >= 0),
  CONSTRAINT chk_order_refund_status CHECK (
    refund_status_code IN ('REQUESTED','APPROVED','DENIED','COMPLETED','CANCELED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
