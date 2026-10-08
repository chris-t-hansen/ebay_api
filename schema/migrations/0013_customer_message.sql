-- 0013_customer_message.sql
-- `content` and `responded_status` from the SKILL.md sketch become message_body plus a real
-- flag/timestamp pair. A message may reference a listing, an order, both, or neither (general
-- enquiries), so those two foreign keys are nullable by design rather than a modelling accident.

CREATE TABLE IF NOT EXISTS customer_message (
  customer_message_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ebay_message_id       VARCHAR(37)         NULL,
  message_thread_key    VARCHAR(80)         NULL COMMENT 'shared value grouping a conversation, usually the item or order reference',
  sender_ebay_user_id   BIGINT UNSIGNED     NULL,
  recipient_ebay_user_id BIGINT UNSIGNED    NULL,
  direction_code        VARCHAR(10)     NOT NULL DEFAULT 'INBOUND',
  message_subject       VARCHAR(200)        NULL,
  message_body          MEDIUMTEXT      NOT NULL,
  message_timestamp_utc DATETIME(6)     NOT NULL,
  message_status_code   VARCHAR(20)     NOT NULL DEFAULT 'NEW',
  responded_flag        TINYINT(1)      NOT NULL DEFAULT 0,
  responded_timestamp_utc DATETIME(6)       NULL,
  response_customer_message_id BIGINT UNSIGNED NULL COMMENT 'self reference to the reply, NULL until answered',
  listing_id            BIGINT UNSIGNED     NULL,
  sale_order_id         BIGINT UNSIGNED     NULL,
  created_by_user       VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  created_timestamp     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_update_user      VARCHAR(255)    NOT NULL DEFAULT CURRENT_USER,
  last_update_timestamp TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_customer_message PRIMARY KEY (customer_message_id),
  CONSTRAINT uq_customer_message_ebay_id UNIQUE (ebay_message_id),
  KEY idx_customer_message_sender_user_id (sender_ebay_user_id),
  KEY idx_customer_message_recipient_user_id (recipient_ebay_user_id),
  KEY idx_customer_message_listing_id (listing_id),
  KEY idx_customer_message_sale_order_id (sale_order_id),
  KEY idx_customer_message_response_id (response_customer_message_id),
  KEY idx_customer_message_thread_time (message_thread_key, message_timestamp_utc),
  FULLTEXT KEY ft_customer_message_subject_body (message_subject, message_body),
  CONSTRAINT fk_customer_message_sender_user FOREIGN KEY (sender_ebay_user_id)
    REFERENCES ebay_user (ebay_user_id) ON DELETE RESTRICT,
  CONSTRAINT fk_customer_message_recipient_user FOREIGN KEY (recipient_ebay_user_id)
    REFERENCES ebay_user (ebay_user_id) ON DELETE RESTRICT,
  CONSTRAINT fk_customer_message_listing FOREIGN KEY (listing_id)
    REFERENCES listing (listing_id) ON DELETE RESTRICT,
  CONSTRAINT fk_customer_message_sale_order FOREIGN KEY (sale_order_id)
    REFERENCES sale_order (sale_order_id) ON DELETE RESTRICT,
  CONSTRAINT fk_customer_message_response FOREIGN KEY (response_customer_message_id)
    REFERENCES customer_message (customer_message_id) ON DELETE RESTRICT,
  CONSTRAINT chk_customer_message_direction CHECK (direction_code IN ('INBOUND','OUTBOUND')),
  CONSTRAINT chk_customer_message_status CHECK (
    message_status_code IN ('NEW','READ','REPLIED','ARCHIVED','SPAM','TRASH')),
  CONSTRAINT chk_customer_message_responded CHECK (
    responded_flag = 0 OR (responded_timestamp_utc IS NOT NULL AND direction_code = 'INBOUND'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
