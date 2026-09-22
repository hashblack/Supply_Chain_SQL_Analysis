-- ============================================================
-- Supplier Performance & Inventory Risk Analysis
-- Heesik Son | Supply chain analysis in SQL (SQLite)
--
-- Dataset: 778 purchase orders, 25 suppliers, 60 SKUs (2025-2026)
-- Every query answers a question a real supply chain team asks.
-- ============================================================


-- ------------------------------------------------------------
-- 1. OTIF (On Time In Full) by supplier
--    The core supplier scorecard metric. A PO counts as OTIF
--    only if it arrived on or before the promised date AND
--    the full quantity was received.
-- ------------------------------------------------------------
SELECT
    s.supplier_name,
    s.country,
    COUNT(*)                                            AS total_pos,
    SUM(CASE WHEN po.received_date <= po.promised_date
              AND po.qty_received  >= po.qty_ordered
             THEN 1 ELSE 0 END)                         AS otif_pos,
    ROUND(100.0 * SUM(CASE WHEN po.received_date <= po.promised_date
                            AND po.qty_received  >= po.qty_ordered
                           THEN 1 ELSE 0 END) / COUNT(*), 1) AS otif_pct
FROM purchase_orders po
JOIN suppliers s ON s.supplier_id = po.supplier_id
GROUP BY s.supplier_name, s.country
HAVING COUNT(*) >= 10
ORDER BY otif_pct ASC;          -- worst performers first: that's where the work is


-- ------------------------------------------------------------
-- 2. Lead time: quoted vs. actual
--    Suppliers quote a lead time at contract. This measures
--    whether they actually hold to it. Positive slip = late.
-- ------------------------------------------------------------
SELECT
    s.supplier_name,
    s.quoted_lead_time_days,
    ROUND(AVG(julianday(po.received_date) - julianday(po.order_date)), 1) AS actual_lead_time,
    ROUND(AVG(julianday(po.received_date) - julianday(po.order_date))
          - s.quoted_lead_time_days, 1)                                   AS slip_days
FROM purchase_orders po
JOIN suppliers s ON s.supplier_id = po.supplier_id
GROUP BY s.supplier_name, s.quoted_lead_time_days
ORDER BY slip_days DESC;


-- ------------------------------------------------------------
-- 3. Fill rate — short shipments
--    Received less than ordered. Drives stockouts downstream.
-- ------------------------------------------------------------
SELECT
    s.supplier_name,
    COUNT(*)                                        AS short_shipments,
    SUM(po.qty_ordered - po.qty_received)           AS total_units_short,
    ROUND(100.0 * SUM(po.qty_received) / SUM(po.qty_ordered), 2) AS fill_rate_pct
FROM purchase_orders po
JOIN suppliers s ON s.supplier_id = po.supplier_id
WHERE po.qty_received < po.qty_ordered
GROUP BY s.supplier_name
ORDER BY total_units_short DESC;


-- ------------------------------------------------------------
-- 4. Landed cost per unit by category
--    Unit price alone is misleading. Freight changes the ranking.
-- ------------------------------------------------------------
SELECT
    p.category,
    ROUND(SUM(po.qty_received * po.unit_cost), 2)                              AS goods_cost,
    ROUND(SUM(po.freight_cost), 2)                                             AS freight_cost,
    ROUND((SUM(po.qty_received * po.unit_cost) + SUM(po.freight_cost))
          / SUM(po.qty_received), 3)                                           AS landed_cost_per_unit,
    ROUND(100.0 * SUM(po.freight_cost)
          / (SUM(po.qty_received * po.unit_cost) + SUM(po.freight_cost)), 1)   AS freight_pct_of_landed
FROM purchase_orders po
JOIN products p ON p.sku = po.sku
GROUP BY p.category
ORDER BY landed_cost_per_unit DESC;


-- ------------------------------------------------------------
-- 5. Suppliers performing worse than average  [SUBQUERY]
--    Everyone below the portfolio-wide OTIF average.
-- ------------------------------------------------------------
WITH supplier_otif AS (
    SELECT
        po.supplier_id,
        100.0 * SUM(CASE WHEN po.received_date <= po.promised_date
                          AND po.qty_received  >= po.qty_ordered
                         THEN 1 ELSE 0 END) / COUNT(*) AS otif_pct
    FROM purchase_orders po
    GROUP BY po.supplier_id
)
SELECT
    s.supplier_name,
    s.country,
    ROUND(so.otif_pct, 1) AS otif_pct
FROM supplier_otif so
JOIN suppliers s ON s.supplier_id = so.supplier_id
WHERE so.otif_pct < (SELECT AVG(otif_pct) FROM supplier_otif)
ORDER BY so.otif_pct ASC;


-- ------------------------------------------------------------
-- 6. Stockout risk — on hand below reorder point
--    Which SKUs need a PO raised now, and who supplies them.
-- ------------------------------------------------------------
SELECT
    p.sku,
    p.description,
    p.category,
    p.on_hand_qty,
    p.reorder_point,
    p.safety_stock,
    p.reorder_point - p.on_hand_qty AS units_below_reorder,
    CASE
        WHEN p.on_hand_qty = 0                     THEN 'STOCKOUT'
        WHEN p.on_hand_qty < p.safety_stock        THEN 'CRITICAL'
        WHEN p.on_hand_qty < p.reorder_point       THEN 'REORDER'
        ELSE 'OK'
    END AS status
FROM products p
WHERE p.on_hand_qty < p.reorder_point
ORDER BY units_below_reorder DESC;


-- ------------------------------------------------------------
-- 7. Monthly spend and on-time trend
--    Feeds the time-series visual in the dashboard.
-- ------------------------------------------------------------
SELECT
    strftime('%Y-%m', po.order_date) AS order_month,
    COUNT(*)                                                   AS po_count,
    ROUND(SUM(po.qty_ordered * po.unit_cost + po.freight_cost), 2) AS total_spend,
    ROUND(100.0 * SUM(CASE WHEN po.received_date <= po.promised_date
                           THEN 1 ELSE 0 END) / COUNT(*), 1)   AS on_time_pct
FROM purchase_orders po
GROUP BY order_month
ORDER BY order_month;


-- ------------------------------------------------------------
-- 8. Country risk concentration
--    How much spend sits in each sourcing country, and how
--    reliable that country's suppliers are. Single-country
--    concentration is a tariff and disruption exposure.
-- ------------------------------------------------------------
SELECT
    s.country,
    COUNT(DISTINCT s.supplier_id)                                    AS supplier_count,
    ROUND(SUM(po.qty_ordered * po.unit_cost + po.freight_cost), 2)   AS total_spend,
    ROUND(100.0 * SUM(po.qty_ordered * po.unit_cost + po.freight_cost)
          / (SELECT SUM(qty_ordered * unit_cost + freight_cost)
             FROM purchase_orders), 1)                               AS pct_of_total_spend,
    ROUND(AVG(julianday(po.received_date) - julianday(po.promised_date)), 1) AS avg_days_late
FROM purchase_orders po
JOIN suppliers s ON s.supplier_id = po.supplier_id
GROUP BY s.country
ORDER BY total_spend DESC;


-- ------------------------------------------------------------
-- 9. Top 10 SKUs by spend  [window function]
--    Where the money actually goes — the 80/20 view.
-- ------------------------------------------------------------
SELECT sku, description, category, sku_spend, spend_rank
FROM (
    SELECT
        p.sku,
        p.description,
        p.category,
        ROUND(SUM(po.qty_ordered * po.unit_cost), 2) AS sku_spend,
        RANK() OVER (ORDER BY SUM(po.qty_ordered * po.unit_cost) DESC) AS spend_rank
    FROM purchase_orders po
    JOIN products p ON p.sku = po.sku
    GROUP BY p.sku, p.description, p.category
)
WHERE spend_rank <= 10;
