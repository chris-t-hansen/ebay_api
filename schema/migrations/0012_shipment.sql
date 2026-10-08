-- 0012_shipment.sql
-- No label file, path, or hash columns: the PDF is printed immediately and backed up in Google
-- Drive. Only the tracking number and the carrier are stored, plus cost and the refund window.
-- created_timestamp doubles as the label purchase time because you buy and print in one sitting,
-- so a separate purchase-timestamp column would be a duplicate-meaning column.

CREATE TABLE IF NOT EXISTS shipment (
  shipment_id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sale_order_id         BIGINT UNSIGNED NOT NULL,
  shipping_carrier_id   BIGINT UNSIGNED NOT NULL COMMENT 'USPS / UPS / FedEx - the vendor you asked for',
  shipping_method_id    BIGINT UNSIGNED     NULL COMMENT 'Priority, Ground Advantage, Media Mail',
  package_spec_id       BIGINT UNSIGNED     NULL COMMENT 'the box actually used',
  tracking_number       VARCHAR(50)         NULL COMMENT 'from shipping_fulfillment - no manual typing needed',
  shipment_status_code  VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
  shipped_timestamp_utc DATETIME(6)         NULL,
  estimated_delivery_timestamp_utc DATETIME(6) NULL,
  delivered_timestamp_utc DATETIME(6)       NULL,
  signature_confirmed_flag TINYINT(1)   NOT NULL DEFAULT 0,
  shipping_cost_amount  DECIMAL(8,2)        NULL COMMENT 'what the label cost you',
  shipping_cost_currency_code CHAR(3)  NOT NULL DEFAULT 'USD',
  insurance_amount      DECIMAL(8,2)        NULL,
  label_refund_deadline_timestamp_utc DATETIME(6) NULL COMMENT 'last moment a refund can be requested',
  label_refund_status_code VARCHAR(20)  NOT NULL DEFAULT 'NOT_ELIGIBLE',
  label_refund_amount   DECIMAL(8,2)        NULL,
  label_refund_requested_timestamp_utc DATETIME(6) NULL,
  ebay_shipment_id      VARCHAR(37)         NULL COMMENT 'Fulfillment API shipping_fulfillment_id',
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_shipment PRIMARY KEY (shipment_id),
  CONSTRAINT uq_shipment_ebay_shipment_id UNIQUE (ebay_shipment_id),
  CONSTRAINT uq_shipment_carrier_tracking UNIQUE (shipping_carrier_id, tracking_number)
    COMMENT 'carrier+number, because tracking numbers are recycled by carriers',
  KEY idx_shipment_sale_order_id (sale_order_id),
  KEY idx_shipment_shipping_method_id (shipping_method_id),
  KEY idx_shipment_package_spec_id (package_spec_id),
  KEY idx_shipment_tracking_number (tracking_number),
  KEY idx_shipment_refund_deadline (label_refund_deadline_timestamp_utc, label_refund_status_code),
  CONSTRAINT fk_shipment_sale_order FOREIGN KEY (sale_order_id)
    REFERENCES sale_order (sale_order_id) ON DELETE RESTRICT,
  CONSTRAINT fk_shipment_shipping_carrier FOREIGN KEY (shipping_carrier_id)
    REFERENCES shipping_carrier (shipping_carrier_id) ON DELETE RESTRICT,
  CONSTRAINT fk_shipment_shipping_method FOREIGN KEY (shipping_method_id)
    REFERENCES shipping_method (shipping_method_id) ON DELETE RESTRICT,
  CONSTRAINT fk_shipment_package_spec FOREIGN KEY (package_spec_id)
    REFERENCES package_spec (package_spec_id) ON DELETE RESTRICT,
  CONSTRAINT chk_shipment_tracking_format CHECK (
    tracking_number IS NULL OR tracking_number REGEXP '^[A-Z0-9]{6,35}$'),
  CONSTRAINT chk_shipment_status CHECK (
    shipment_status_code IN ('PENDING','LABELED','IN_TRANSIT','DELIVERED','RETURNED','CANCELED')),
  CONSTRAINT chk_shipment_refund_status CHECK (
    label_refund_status_code IN ('NOT_ELIGIBLE','NOT_REQUESTED','REQUESTED','REFUNDED','EXPIRED')),
  CONSTRAINT chk_shipment_amounts CHECK (
    (shipping_cost_amount IS NULL OR shipping_cost_amount >= 0)
    AND (insurance_amount IS NULL OR insurance_amount >= 0)
    AND (label_refund_amount IS NULL OR label_refund_amount >= 0)),
  CONSTRAINT chk_shipment_delivery_window CHECK (
    delivered_timestamp_utc IS NULL OR shipped_timestamp_utc IS NULL
    OR delivered_timestamp_utc >= shipped_timestamp_utc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS shipment_line_item (
  shipment_line_item_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  shipment_id           BIGINT UNSIGNED NOT NULL,
  sale_order_line_item_id BIGINT UNSIGNED NOT NULL,
  shipped_quantity_units INT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'supports a partial shipment of a multi-quantity line',
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_shipment_line_item PRIMARY KEY (shipment_line_item_id),
  CONSTRAINT uq_shipment_line_item_pair UNIQUE (shipment_id, sale_order_line_item_id),
  KEY idx_shipment_line_item_line_item_id (sale_order_line_item_id),
  CONSTRAINT fk_shipment_line_item_shipment FOREIGN KEY (shipment_id)
    REFERENCES shipment (shipment_id) ON DELETE CASCADE,
  CONSTRAINT fk_shipment_line_item_line_item FOREIGN KEY (sale_order_line_item_id)
    REFERENCES sale_order_line_item (sale_order_line_item_id) ON DELETE CASCADE,
  CONSTRAINT chk_shipment_line_quantity CHECK (shipped_quantity_units > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
