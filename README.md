# Supply Chain Analysis — Supplier Performance & Inventory Risk

SQL analysis of a cosmetics import operation: 778 purchase orders, 25 suppliers across 8 countries, 60 SKUs.

## Questions answered
- Which suppliers miss OTIF (on-time-in-full), and by how much?
- Where does quoted lead time diverge from actual delivery time?
- What is landed cost per unit once freight is included?
- Which SKUs are below reorder point right now?
- How concentrated is spend by sourcing country?
- Where does the money actually go — top SKUs by spend?

## Key findings
- Worst-performing supplier delivers 61.3% OTIF vs. 100% for the best performer
- South Korea and China together account for 45.9% of total spend — a tariff and disruption exposure concentrated in two countries
- 12 of 60 SKUs are currently below reorder point and require replenishment

## Approach
Wrote 9 SQL queries against a SQLite database covering joins, aggregation, CTEs, subqueries, window functions, date arithmetic, and CASE logic — the techniques used to build a supplier scorecard from raw transactional data.

## Tools
SQL (SQLite) — joins, CTEs, subqueries, window functions (RANK), date math, conditional aggregation

## Files
- `queries.sql` — 9 analysis queries
- `suppliers.csv` — supplier data
- `products.csv` — product/SKU data
- `purchase_orders.csv` — purchase order transactions
- `supply_chain.db` — SQLite database, tables pre-loaded

## Author
Heesik Son — [LinkedIn](https://www.linkedin.com/in/heesik-son) . Heesikson@gmail.com
