-- ============================================================
-- Superstore SQL Project - Phase 1: AUDIT (read-only)
-- File: sql/01_audit.sql
-- Purpose: audit orders_raw (imported EXACTLY as it comes from the
--          classic Kaggle "Sample - Superstore.csv", 9,994 rows).
-- Rule: NO data is changed in this phase. All issues found here are
--       logged and fixed later in 02_clean.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1. ROW COUNT
-- Expected: 9,994 (classic Superstore file)
-- ------------------------------------------------------------
SELECT COUNT(*) AS total FROM orders_raw;
-- output: 9994  ✔ matches the classic file exactly

-- ------------------------------------------------------------
-- 2. NULLS / BLANKS ON KEY COLUMNS
-- Checks whether any key column is NULL or an empty string.
-- ------------------------------------------------------------
SELECT
  SUM(`Order ID`   IS NULL OR TRIM(`Order ID`)   = '') AS null_order_id,
  SUM(`Order Date` IS NULL OR TRIM(`Order Date`) = '') AS null_order_date,
  SUM(`Sales`      IS NULL OR TRIM(`Sales`)      = '') AS null_sales,
  SUM(`Profit`     IS NULL OR TRIM(`Profit`)     = '') AS null_profit
FROM orders_raw;
-- output: 0, 0, 0, 0  ✔ no nulls/blanks on these four key columns

-- ------------------------------------------------------------
-- 3. DUPLICATES
-- 3a. Row ID must be unique (it is the row identifier).
-- 3b. Same Order ID + Product ID appearing twice -> possible
--     duplicate order lines (the main issue found in this audit).
-- 3c. Full duplicate-group count (confirms nothing hidden by LIMIT).
-- 3d. Are the duplicate pairs identical or partial?
--     Identical -> true duplicate, keep one row in Phase 2.
--     Partial   -> legitimate separate line items, keep both.
-- ------------------------------------------------------------
-- 3a. duplicate Row ID
SELECT `Row ID`, COUNT(*) c FROM orders_raw GROUP BY `Row ID` HAVING c > 1;
-- output: empty  ✔ Row ID is unique

-- 3b. duplicate Order ID + Product ID
SELECT `Order ID`, `Product ID`, COUNT(*) c FROM orders_raw
GROUP BY `Order ID`, `Product ID` HAVING c > 1 LIMIT 10;
-- output: 8 groups (each c = 2):
--   CA-2016-129714  OFF-PA-10001970
--   US-2016-123750  TEC-AC-10004659
--   CA-2016-137043  FUR-FU-10003664
--   CA-2017-152912  OFF-ST-10003208
--   US-2014-150119  FUR-CH-10002965
--   CA-2015-103135  OFF-BI-10000069
--   CA-2017-118017  TEC-AC-10002006
--   CA-2016-140571  OFF-PA-10001954

-- 3c. full duplicate-group count
SELECT COUNT(*) AS dupe_groups FROM (
  SELECT `Order ID`, `Product ID` FROM orders_raw
  GROUP BY `Order ID`, `Product ID` HAVING COUNT(*) > 1
) d;
-- output: 8  ✔ (same as the LIMIT 10 sample; nothing was hidden)

-- 3d. identical or partial duplicates?
SELECT * FROM orders_raw
WHERE (`Order ID`, `Product ID`) IN (
  SELECT `Order ID`, `Product ID` FROM orders_raw
  GROUP BY `Order ID`, `Product ID` HAVING COUNT(*) > 1
) ORDER BY `Order ID`, `Product ID` LIMIT 20;
-- output: 16 rows (8 pairs x 2 rows each).
-- CONCLUSION: 7 pairs differ in Sales/Quantity/Profit -> legitimate separate
--   line items (same product ordered twice in one order), NOT errors, keep both.
-- 1 pair is fully identical except Row ID: US-2014-150119 (Row ID 3406/3407)
--   -> true duplicate, remove 1 row in Phase 2.
-- (full 16-row result pasted in superstore-local.session.sql)

-- ------------------------------------------------------------
-- 4. TEXT CONSISTENCY (casing / distinct values / stray spaces)
-- ------------------------------------------------------------
-- 4a. distinct values look correct (no mixed casing)
SELECT DISTINCT Category FROM orders_raw;
-- output: Furniture / Office Supplies / Technology  ✔ clean

SELECT DISTINCT Region FROM orders_raw;
-- output: South / West / Central / East  ✔ clean

SELECT DISTINCT `Ship Mode` FROM orders_raw;
-- output: Second Class / Standard Class / First Class / Same Day  ✔ clean

-- 4b. spacing check on Category
SELECT Category, TRIM(Category), COUNT(*) FROM orders_raw
GROUP BY Category, TRIM(Category);
-- output: TRIM(Category) = Category for all rows (2121 / 6026 / 1847)  ✔

-- 4c. spacing check on Region / Ship Mode
SELECT * FROM orders_raw
WHERE `Region` != TRIM(`Region`) OR `Ship Mode` != TRIM(`Ship Mode`) LIMIT 10;
-- output: empty  ✔ no stray spaces in Region or Ship Mode

-- 4d. spacing check on Customer Name / City / State / Product Name
SELECT * FROM orders_raw
WHERE `Customer Name` != TRIM(`Customer Name`)
   OR `City` != TRIM(`City`)
   OR `State` != TRIM(`State`)
   OR `Product Name` != TRIM(`Product Name`) LIMIT 10;
-- output: 16 rows affected -> stray whitespace IS present in the data.
-- Observed pattern: all 16 rows involve only 3 product names (Kensington
-- SlimBlade Note, Anker Ultrathin Bluetooth W, Iceberg Mobile Mega Data/) -
-- whitespace clusters on specific products, likely a data-entry/export artifact.

-- 4e. which column carries the stray whitespace
SELECT
  SUM(`Customer Name` != TRIM(`Customer Name`)) AS bad_customer_name,
  SUM(`City` != TRIM(`City`))                   AS bad_city,
  SUM(`State` != TRIM(`State`))                 AS bad_state,
  SUM(`Product Name` != TRIM(`Product Name`))   AS bad_product_name
FROM orders_raw;
-- output: bad_customer_name=0, bad_city=0, bad_state=0, bad_product_name=16
-- All stray whitespace is in Product Name only (16 rows), clustered on 3 products.

-- ------------------------------------------------------------
-- 5. IMPOSSIBLE VALUES
-- Columns are TEXT in orders_raw (by design), so CAST first.
-- 5a. Discount must be within 0-1.
-- 5b. Quantity must be >= 1.
-- ------------------------------------------------------------
-- 5a. discount range check
SELECT * FROM orders_raw
WHERE CAST(Discount AS DECIMAL(10, 4)) < 0
   OR CAST(Discount AS DECIMAL(10, 4)) > 1 LIMIT 10;
-- output: empty  ✔ all discounts within 0-1

-- 5b. quantity check
SELECT * FROM orders_raw
WHERE CAST(Quantity AS SIGNED) <= 0 LIMIT 10;
-- output: empty  ✔ no zero/negative quantities

-- ------------------------------------------------------------
-- 6. DATES STORED AS TEXT + SHIP DATE BEFORE ORDER DATE
-- Dates arrive as text in M/D/YYYY format. Verify STR_TO_DATE parses
-- them, then check the impossible case Ship Date < Order Date.
-- ------------------------------------------------------------
-- 6a. date parsing sanity
SELECT `Order Date`, STR_TO_DATE(`Order Date`, '%m/%d/%Y') AS parsed
FROM orders_raw LIMIT 5;
-- output: 5 rows, both columns show valid dates  ✔ format is M/D/YYYY

-- 6b. impossible date ranges
SELECT `Order ID`, `Order Date`, `Ship Date`
FROM orders_raw
WHERE STR_TO_DATE(`Ship Date`, '%m/%d/%Y') < STR_TO_DATE(`Order Date`, '%m/%d/%Y')
LIMIT 10;
-- output: empty  ✔ no impossible date ranges

-- ------------------------------------------------------------
-- 7. ENCODING NOTE (finding, not a query)
-- Some Product Name values contain the U+FFFD replacement character
-- from CSV encoding, e.g. the "Imation...Secure+ Hardware Encrypted USB
-- ...Flash Drive; 16GB" product (Row IDs 431-432, order US-2016-123750).
-- Decision: kept as-is in orders_raw (raw data is never modified).
-- Phase 2 will standardize, or this is documented as a data limitation.
-- ------------------------------------------------------------

-- ============================================================
-- PHASE 1 SUMMARY (audit findings)
-- ============================================================
--  1. Row count ..................... 9,994           ✔ ok
--  2. Nulls/blanks (key cols) ....... 0               ✔ ok
--  3. Duplicates .................... 8 groups        ✖ 1 true duplicate
--                                     (Row ID unique; 7 legit multi-line
--                                      orders; 1 identical pair: Row ID 3407)
--  4. Text consistency .............. 16 rows         ✖ stray whitespace,
--                                     Product Name only (3 products)
--  5. Impossible values ............. 0               ✔ ok
--                                     (discount 0-1 ✔, quantity >= 1 ✔)
--  6. Dates as text / bad ranges .... parse ok, 0     ✔ ok
--  7. Encoding artifacts (U+FFFD) ... 1 product       ✖ documented decision
--
-- The file is much cleaner than a messy variant would be - documented
-- honestly. Phase 2 fixes: dedupe (1 row), TRIM Product Name (16 rows),
-- type casting, then build orders_clean + cleaning log.
-- ============================================================
