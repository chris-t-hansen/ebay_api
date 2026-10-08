-- 0005_inventory_item_children.sql
-- Photos and item specifics are child tables: SKILL.md forbids JSON columns, and both are
-- multi-valued, so a column on inventory_item would violate 1NF/3NF.

CREATE TABLE IF NOT EXISTS inventory_item_photo (
  inventory_item_photo_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  inventory_item_id     BIGINT UNSIGNED NOT NULL,
  photo_file_path       VARCHAR(500) NOT NULL COMMENT 'local master file; uploaded to eBay Media API before publish',
  sort_order            SMALLINT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'position on the eBay listing, 1 = primary',
  photo_width_pixels    INT UNSIGNED     NULL,
  photo_height_pixels   INT UNSIGNED     NULL,
  photo_byte_size       BIGINT UNSIGNED  NULL,
  media_api_reference_id VARCHAR(37)     NULL COMMENT 'reference returned by the Media API upload',
  media_upload_timestamp_utc DATETIME(6) NULL,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_inventory_item_photo PRIMARY KEY (inventory_item_photo_id),
  CONSTRAINT uq_inventory_item_photo_order UNIQUE (inventory_item_id, sort_order),
  CONSTRAINT fk_inventory_item_photo_item FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_item (inventory_item_id) ON DELETE CASCADE,
  CONSTRAINT chk_inventory_item_photo_order CHECK (sort_order > 0),
  CONSTRAINT chk_inventory_item_photo_size CHECK (photo_byte_size IS NULL OR photo_byte_size > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

CREATE TABLE IF NOT EXISTS inventory_item_attribute (
  inventory_item_attribute_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  inventory_item_id     BIGINT UNSIGNED NOT NULL,
  attribute_name        VARCHAR(80)  NOT NULL COMMENT 'eBay aspect name, e.g. Artist, Label, Release Name',
  attribute_value       VARCHAR(250) NOT NULL COMMENT 'use the literal DoesNotApply for missing UPC-style identifiers',
  attribute_sequence_number SMALLINT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'supports multi-valued aspects such as Colour/Size',
  required_flag         TINYINT(1)   NOT NULL DEFAULT 0,
  created_by_user       VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255) NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_inventory_item_attribute PRIMARY KEY (inventory_item_attribute_id),
  CONSTRAINT uq_inventory_item_attribute_value UNIQUE (inventory_item_id, attribute_name, attribute_value),
  KEY idx_inventory_item_attribute_lookup (attribute_name, attribute_value),
  KEY idx_inventory_item_attribute_sequence (inventory_item_id, attribute_sequence_number),
  CONSTRAINT fk_inventory_item_attribute_item FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_item (inventory_item_id) ON DELETE CASCADE,
  CONSTRAINT chk_inventory_item_attribute_sequence CHECK (attribute_sequence_number > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
