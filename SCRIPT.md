# Superstore SQL Project — Work Log (SCRIPT.md)

Project: Clean the Superstore data, then find what's losing money
Business question: Which categories, regions, and discount levels are losing money, and what should the company change?

Stack: MySQL 8.x + VS Code (SQLTools + MySQL driver) + MySQL Workbench (import only)
Repo: D:\ECommerce (folders: sql/, data/raw, data/exports, docs/, charts/, dashboard/)

---

## Phase 0 — Setup (Day 1)

### 1. Database tooling
- MySQL Server 8.x running (verified with `SELECT 1` and `SHOW DATABASES`).
- VS Code SQLTools configured:
  - Driver: SQLTools MySQL/MariaDB
  - Connection name: `superstore-local`
  - Server: localhost, Port: 3306, User: root
  - Password mode: `Ask on connect` (never saved)
- First connection failed with `Unknown database 'superstore'` → fixed by creating the DB first (Step 2 below), then re-testing connection → success.

### 2. Dataset
- Chosen on purpose: the **classic** Kaggle Superstore file (not a "cleaned"/modernized variant) so the sanity check is verifiable.
- Searched Kaggle for: `Sample - Superstore`
- Matched this fingerprint: file `Sample - Superstore.csv`, ~2.29 MB, 9,994 rows, 21 columns, dates 2014–2017 in `M/D/YYYY` format.
- Saved untouched (no edits) as: `data/raw/superstore.csv`
- 21 columns: Row ID, Order ID, Order Date, Ship Date, Ship Mode, Customer ID, Customer Name,
  Segment, Country, City, State, Postal Code, Region, Product ID, Category, Sub-Category,
  Product Name, Sales, Quantity, Discount, Profit

---

## Phase 1 — Load & Audit (Day 1) — ✔ COMPLETE

### 3. Database + raw staging table
Principle: import EXACTLY as it comes. No changing values yet — everything is TEXT so the
audit can see text-dates, stray spaces, and casing issues as they truly are.

```sql
CREATE DATABASE superstore;
```

```sql
USE superstore;
CREATE TABLE orders_raw (
  `Row ID` TEXT,
  `Order ID` TEXT,
  `Order Date` TEXT,
  `Ship Date` TEXT,
  `Ship Mode` TEXT,
  `Customer ID` TEXT,
  `Customer Name` TEXT,
  `Segment` TEXT,
  `Country` TEXT,
  `City` TEXT,
  `State` TEXT,
  `Postal Code` TEXT,
  `Region` TEXT,
  `Product ID` TEXT,
  `Category` TEXT,
  `Sub-Category` TEXT,
  `Product Name` TEXT,
  `Sales` TEXT,
  `Quantity` TEXT,
  `Discount` TEXT,
  `Profit` TEXT
);
```

### 4. Import
- Tool: MySQL Workbench → Table Data Import Wizard → `D:\ECommerce\data\raw\superstore.csv`
  → target `orders_raw` (use existing table), UTF-8.
- SQLTools alone was used for queries; Workbench only for the CSV load.

### 5. Load sanity check
```sql
SELECT COUNT(*) AS total FROM orders_raw;
-- ✔ Result: 9994 (matches the classic file exactly)

SELECT * FROM orders_raw LIMIT 3;
-- ✔ Row IDs 1..9994 present as expected
```

### 6. Final audit results (all queries in sql/01_audit.sql)

| # | Check                          | Result                          | Status        |
|---|--------------------------------|---------------------------------|---------------|
| 1 | Row count                      | 9,994                           | ✔ ok          |
| 2 | Nulls/blanks (key cols)        | 0                               | ✔ ok          |
| 3 | Duplicate Row ID               | 0                               | ✔ ok          |
| 4 | Duplicate Order ID + Product ID| 8 groups                        | ✖ see below   |
| 5 | Casing (Category/Region/Mode)  | distinct values clean           | ✔ ok          |
| 6 | Extra spaces                   | 16 rows, Product Name only      | ✖ Phase 2 fix |
| 7 | Discount outside 0–1           | 0                               | ✔ ok          |
| 8 | Quantity ≤ 0                   | 0                               | ✔ ok          |
| 9 | Ship Date < Order Date         | 0                               | ✔ ok          |
|10 | Dates stored as text           | confirmed; M/D/YYYY parses      | ✔ Phase 2 fix |
|11 | Encoding artifacts (U+FFFD)    | 1 product (Imation USB drive)   | ✖ documented  |

### 7. The three real findings (Phase 2's input)

1. **True duplicate row** — of 8 groups sharing Order ID + Product ID, 7 are legitimate
   separate line items (different Sales/Quantity — same product ordered twice in one
   order, keep both). 1 pair is fully identical except Row ID:
   `US-2014-150119` (Row ID 3406/3407, Global Leather Highback Chair).
   → Phase 2 fix: remove exactly 1 row via ROW_NUMBER() dedupe.
2. **Stray whitespace** — 16 rows, all in Product Name, clustered on just 3 products
   (Kensington SlimBlade Note, Anker Ultrathin Bluetooth W, Iceberg Mobile Mega Data/).
   → Phase 2 fix: TRIM(Product Name) when building orders_clean.
3. **Encoding artifact** — U+FFFD replacement char in the Imation USB product name
   (Row IDs 431–432). Decision: kept as-is in raw; standardize in Phase 2 or
   document as a data limitation in the README.

Honest note for the README: the classic Superstore file is mostly clean — the audit
found only these 3 small issues, all documented with decisions.

### 8. Deliverables produced
- `sql/01_audit.sql` — clean, sequentially numbered audit file with recorded outputs
  and a Phase 1 summary table (GitHub-ready).
- `superstore-local.session.sql` — raw working log (kept for reference).

---

## Phase 2 — Clean (next)
- Staging copy of orders_raw → dedupe with ROW_NUMBER() in a CTE (remove Row ID 3407)
- TRIM(Product Name) — 16 rows
- TRIM all text columns defensively; UPPER/standardize where needed
- CAST columns to proper types: dates via STR_TO_DATE('%m/%d/%Y'),
  Sales/Profit/Discount DECIMAL, Quantity SIGNED, Postal Code keep as text (leading zeros)
- Build `orders_clean` table
- Create `docs/cleaning_log.md`: issue | rows affected | fix | why (3 findings above)

## Phase 3 — Analysis (after Phase 2)
Nine business questions incl. discount-band CASE analysis, loss-making set, region/state
profit, ship-mode vs profit, top customers profit-vs-sales, YoY growth, category × discount.

---

## How this file is kept updated
- Run each query in `superstore-local.session.sql`.
- Write one `-- output: ...` comment next to the query immediately.
- Update the status table (Section 6) after every batch.
- Finalized findings move to `docs/cleaning_log.md` in Phase 2.
