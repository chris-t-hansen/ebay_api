-- 0002_shipping_and_policy_reference.sql
-- Carriers are normalised out of shipping_method: "vendor" is functionally dependent on the
-- service name ("USPS Priority" -> USPS), so storing it on shipping_method would be a
-- transitive dependency (3NF violation).

CREATE TABLE IF NOT EXISTS shipping_carrier (
  shipping_carrier_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  carrier_code          VARCHAR(20)  NOT NULL COMMENT 'USPS, UPS, FEDEX, ONTRAC',
  carrier_name          VARCHAR(60)  NOT NULL,
  ebay_carrier_code     VARCHAR(20)      NULL COMMENT 'raw value seen in eBay shippingCarrierCode',
  tracking_url_template VARCHAR(200)     NULL COMMENT '%s is replaced with the tracking number',
  active_flag           TINYINT(1)   NOT NULL DEFAULT 1,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_shipping_carrier PRIMARY KEY (shipping_carrier_id),
  CONSTRAINT uq_shipping_carrier_code UNIQUE (carrier_code),
  CONSTRAINT chk_shipping_carrier_code CHECK (carrier_code REGEXP '^[A-Z0-9_]{2,20}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS shipping_method (
  shipping_method_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  shipping_carrier_id   BIGINT UNSIGNED NOT NULL,
  shipping_method_name  VARCHAR(100) NOT NULL COMMENT 'USPS Priority Mail, USPS Ground Advantage, USPS Media Mail',
  carrier_service_code  VARCHAR(30)      NULL COMMENT 'carrier-side service identifier',
  ebay_shipping_service VARCHAR(50)      NULL COMMENT 'value expected by eBay fulfillment policies',
  service_region_code   VARCHAR(20)  NOT NULL DEFAULT 'DOMESTIC',
  tracking_required_flag TINYINT(1)  NOT NULL DEFAULT 1,
  max_weight_ounces     DECIMAL(9,2)     NULL COMMENT 'service limit; NULL = not published',
  active_flag           TINYINT(1)   NOT NULL DEFAULT 1,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_shipping_method PRIMARY KEY (shipping_method_id),
  CONSTRAINT uq_shipping_method_name UNIQUE (shipping_method_name),
  KEY idx_shipping_method_carrier_id (shipping_carrier_id),
  CONSTRAINT fk_shipping_method_carrier FOREIGN KEY (shipping_carrier_id)
    REFERENCES shipping_carrier (shipping_carrier_id) ON DELETE RESTRICT,
  CONSTRAINT chk_shipping_method_region CHECK (service_region_code IN ('DOMESTIC','INTERNATIONAL','WORLDWIDE')),
  CONSTRAINT chk_shipping_method_max_weight CHECK (max_weight_ounces IS NULL OR max_weight_ounces > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS business_policy (
  business_policy_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  policy_type_code      VARCHAR(20)  NOT NULL COMMENT 'PAYMENT, FULFILLMENT, RETURN - all three are required on an eBay offer',
  policy_name           VARCHAR(100) NOT NULL,
  ebay_policy_id        VARCHAR(37)      NULL,
  ebay_marketplace_id   BIGINT UNSIGNED NOT NULL,
  archived_flag         TINYINT(1)   NOT NULL DEFAULT 0,
  policy_effective_date DATE             NULL,
  last_sync_timestamp_utc DATETIME(6)    NULL,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_business_policy PRIMARY KEY (business_policy_id),
  CONSTRAINT uq_business_policy_type_name UNIQUE (policy_type_code, policy_name),
  KEY idx_business_policy_marketplace_id (ebay_marketplace_id),
  CONSTRAINT fk_business_policy_marketplace FOREIGN KEY (ebay_marketplace_id)
    REFERENCES ebay_marketplace (ebay_marketplace_id) ON DELETE RESTRICT,
  CONSTRAINT chk_business_policy_type CHECK (policy_type_code IN ('PAYMENT','FULFILLMENT','RETURN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS inventory_location (
  inventory_location_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  location_code         VARCHAR(50)  NOT NULL COMMENT 'merchantBusinessLocationId, e.g. HOME-PRIMARY',
  location_name         VARCHAR(80)  NOT NULL,
  contact_name          VARCHAR(100)     NULL,
  contact_phone_number  VARCHAR(30)      NULL,
  street_address_line1  VARCHAR(120) NOT NULL,
  street_address_line2  VARCHAR(120)     NULL,
  city_name             VARCHAR(60)  NOT NULL,
  state_province_code   VARCHAR(20)  NOT NULL,
  postal_code           VARCHAR(16)  NOT NULL COMMENT 'the ship-from ZIP; listing_shipping points here instead of repeating it',
  country_code          CHAR(2)      NOT NULL DEFAULT 'US',
  timezone_code         VARCHAR(60)  NOT NULL DEFAULT 'America/Los_Angeles',
  cut_time_local        TIME             NULL COMMENT 'local order cut-off for same-day handling',
  active_flag           TINYINT(1)   NOT NULL DEFAULT 1,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_inventory_location PRIMARY KEY (inventory_location_id),
  CONSTRAINT uq_inventory_location_code UNIQUE (location_code),
  CONSTRAINT chk_inventory_location_postal CHECK (postal_code REGEXP '^[A-Z0-9][A-Z0-9 -]{2,14}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
