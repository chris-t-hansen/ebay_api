-- 0014_seed_reference_data.sql
-- Only reference rows that never depend on your eBay account are seeded here.
-- Deliberately NOT seeded:
--   inventory_location  -> needs your real home address
--   business_policy     -> must be read from the Account API (real ebay_policy_id values)
--   package_spec        -> your boxes, your measurements
-- item_condition.ebay_condition_id is left NULL on purpose: the numeric conditionIds differ per
-- category (Records uses a media-condition ladder, general used goods a different one), so they
-- must be confirmed against the Sell Metadata API before any offer is published.

INSERT IGNORE INTO ebay_marketplace
  (marketplace_code, marketplace_name, ebay_site_id, currency_code, locale_code, environment_code)
VALUES
  ('EBAY_US', 'eBay US', '0', 'USD', 'en-US', 'SANDBOX'),
  ('EBAY_US', 'eBay US', '0', 'USD', 'en-US', 'PRODUCTION');

INSERT IGNORE INTO shipping_carrier
  (carrier_code, carrier_name, ebay_carrier_code, tracking_url_template)
VALUES
  ('USPS',  'United States Postal Service', 'USPS',  'https://tools.usps.com/go/TrackConfirmAction?tLabels=%s'),
  ('UPS',   'United Parcel Service',        'UPS',   'https://www.ups.com/track?tracknum=%s'),
  ('FEDEX', 'FedEx',                        'FEDEX', 'https://www.fedex.com/fedextrack/?trknbr=%s'),
  ('ONTRAC','OnTrac',                       'ONTRAC','https://www.ontrac.com/trackingdet.asp?trackingno=%s'),
  ('OTHER', 'Other or unconfirmed carrier', NULL,    NULL);

INSERT IGNORE INTO shipping_method
  (shipping_carrier_id, shipping_method_name, ebay_shipping_service, service_region_code, tracking_required_flag, max_weight_ounces)
SELECT shipping_carrier_id, 'USPS Priority Mail',        'Priority',      'DOMESTIC', 1, 1536.00 FROM shipping_carrier WHERE carrier_code = 'USPS'
UNION ALL SELECT shipping_carrier_id, 'USPS Ground Advantage', 'GroundAdvantage', 'DOMESTIC', 1, 1536.00 FROM shipping_carrier WHERE carrier_code = 'USPS'
UNION ALL SELECT shipping_carrier_id, 'USPS Media Mail',       'Media',         'DOMESTIC', 1, 1536.00 FROM shipping_carrier WHERE carrier_code = 'USPS'
UNION ALL SELECT shipping_carrier_id, 'USPS Large Flat Rate Box', 'LargeFlatRateBox', 'DOMESTIC', 1, 70.00 FROM shipping_carrier WHERE carrier_code = 'USPS'
UNION ALL SELECT shipping_carrier_id, 'UPS Ground',            'Ground',        'DOMESTIC', 1, NULL FROM shipping_carrier WHERE carrier_code = 'UPS'
UNION ALL SELECT shipping_carrier_id, 'FedEx Home Delivery',   'HomeDelivery',  'DOMESTIC', 1, NULL FROM shipping_carrier WHERE carrier_code = 'FEDEX';

INSERT IGNORE INTO item_condition
  (condition_code, condition_name, severity_sequence_number)
VALUES
  ('NEW',        'New (never used)',          1),
  ('LIKE_NEW',   'Like New / as new',         2),
  ('VERY_GOOD',  'Very Good - minor wear',    3),
  ('GOOD',       'Good - visible wear',       4),
  ('FAIR',       'Fair - heavy wear',         5),
  ('FOR_PARTS',  'For Parts or Not Working',  6);
