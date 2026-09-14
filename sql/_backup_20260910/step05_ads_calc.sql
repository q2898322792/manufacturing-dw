-- 先清空应用层报表表（全量重建；表名带库前缀，不依赖 USE 选择默认库）
TRUNCATE TABLE ads_db.ads_boss_dashboard;
TRUNCATE TABLE ads_db.ads_sale_analysis;
TRUNCATE TABLE ads_db.ads_produce_monitor;
TRUNCATE TABLE ads_db.ads_stock_health;
TRUNCATE TABLE ads_db.ads_cost_profit;
TRUNCATE TABLE ads_db.ads_alert_warning;
-- 6. 经营总览大屏
INSERT INTO ads_db.ads_boss_dashboard (stat_date, total_revenue, total_profit, profit_rate, capacity_achieved, inventory_turnover, order_fulfill_rate, material_cost_ratio, labor_cost_ratio, mfg_cost_ratio)
SELECT
    CURDATE() AS stat_date,
    COALESCE(SUM(order_amt), 0) AS total_revenue,
    COALESCE(SUM(order_amt) * 0.15, 0) AS total_profit,
    15.00 AS profit_rate,
    (SELECT COALESCE(AVG(oee_rate), 0) FROM dws_db.dws_produce_day WHERE stat_date BETWEEN '2025-10-01' AND '2026-06-30') AS capacity_achieved,
    45.00 AS inventory_turnover,
    COALESCE(SUM(delivery_ontime_cnt) * 100.0 / NULLIF(SUM(order_cnt), 0), 0) AS order_fulfill_rate,
    45.00 AS material_cost_ratio,
    25.00 AS labor_cost_ratio,
    30.00 AS mfg_cost_ratio
FROM dws_db.dws_sale_day
WHERE stat_date BETWEEN '2025-10-01' AND '2026-06-30';
-- 7. 销售分析报表
TRUNCATE TABLE ads_db.ads_sale_analysis;
INSERT INTO ads_db.ads_sale_analysis (stat_date, customer_id, customer_name, product_id, product_name, region, order_cnt, order_amt, paid_amt, return_amt, delivery_ontime_rate)
SELECT
    s.stat_date,
    s.customer_id,
    c.customer_name,
    s.product_id,
    p.product_name,
    s.region,
    s.order_cnt,
    s.order_amt,
    s.paid_amt,
    s.return_amt,
    ROUND(s.delivery_ontime_cnt * 100.0 / NULLIF(s.order_cnt, 0), 2) AS delivery_ontime_rate
FROM dws_db.dws_sale_day s
LEFT JOIN dwd_db.dim_customer c ON s.customer_id = c.customer_id
LEFT JOIN dwd_db.dim_product p ON s.product_id = p.product_id
WHERE s.stat_date BETWEEN '2025-10-01' AND '2026-06-30';

-- 8. 生产监控报表
TRUNCATE TABLE ads_db.ads_produce_monitor;
INSERT INTO ads_db.ads_produce_monitor (stat_date, workshop_id, workshop_name, product_id, product_name, plan_qty, actual_qty, qualified_qty, defect_qty, defect_type, capacity_achieved, qualified_rate)
SELECT
    p.stat_date,
    p.workshop_id,
    w.workshop_name,
    p.product_id,
    pr.product_name,
    p.plan_qty,
    p.actual_qty,
    p.qualified_qty,
    p.defect_qty,
    '尺寸偏差' AS defect_type,
    ROUND(p.actual_qty * 100.0 / NULLIF(p.plan_qty, 0), 2) AS capacity_achieved,
    ROUND(p.qualified_qty * 100.0 / NULLIF(p.actual_qty, 0), 2) AS qualified_rate
FROM dws_db.dws_produce_day p
LEFT JOIN dwd_db.dim_workshop w ON p.workshop_id = w.workshop_id
LEFT JOIN dwd_db.dim_product pr ON p.product_id = pr.product_id
WHERE p.stat_date BETWEEN '2025-10-01' AND '2026-06-30';

-- 9. 库存健康度报表（今日快照）
INSERT INTO ads_db.ads_stock_health (stat_date, material_id, material_name, warehouse_id, stock_qty, stock_amt, turnover_days, is_slow_moving)
SELECT
    CURDATE() AS stat_date,
    s.material_id,
    m.material_name,
    s.warehouse_id,
    s.stock_qty,
    s.stock_amt,
    45.00 AS turnover_days,
    CASE WHEN s.stock_qty > 1000 AND s.stock_qty < 10000 THEN 1 ELSE 0 END AS is_slow_moving
FROM dws_db.dws_stock_day s
LEFT JOIN dwd_db.dim_material m ON s.material_id = m.material_id
WHERE s.stat_date = (SELECT MAX(stat_date) FROM dws_db.dws_stock_day)
ORDER BY s.stock_amt DESC
LIMIT 100;

-- 10. 成本利润分析（最近3个月）
INSERT INTO ads_db.ads_cost_profit (stat_month, product_id, product_name, workshop_id, workshop_name, material_cost, labor_cost, mfg_cost, total_cost, unit_cost, sale_price, unit_profit, profit_rate)
SELECT
    c.stat_month,
    c.product_id,
    p.product_name,
    c.workshop_id,
    w.workshop_name,
    c.material_cost,
    c.labor_cost,
    c.mfg_cost,
    c.total_cost,
    c.unit_cost,
    ROUND(c.unit_cost * 1.3, 2) AS sale_price,
    ROUND(c.unit_cost * 0.3, 2) AS unit_profit,
    23.08 AS profit_rate
FROM dws_db.dws_cost_month c
LEFT JOIN dwd_db.dim_product p ON c.product_id = p.product_id
LEFT JOIN dwd_db.dim_workshop w ON c.workshop_id = w.workshop_id
WHERE c.stat_month >= DATE_FORMAT(CURDATE() - INTERVAL 3 MONTH, '%Y-%m');

-- 11. 异常预警清单（产能不足预警）
TRUNCATE TABLE ads_db.ads_alert_warning;
INSERT INTO ads_db.ads_alert_warning (alert_id, alert_date, alert_type, alert_level, target_name, target_id, current_value, threshold_value, alert_desc, is_resolved)
SELECT
    CONCAT('ALERT-', DATE_FORMAT(NOW(), '%Y%m%d'), '-', ROW_NUMBER() OVER (ORDER BY p.stat_date)) AS alert_id,
    CURDATE() AS alert_date,
    '产能不足' AS alert_type,
    '高' AS alert_level,
    w.workshop_name AS target_name,
    p.workshop_id AS target_id,
    CONCAT(ROUND(p.actual_qty * 100.0 / NULLIF(p.plan_qty, 0), 0), '%') AS current_value,
    '80%' AS threshold_value,
    CONCAT(w.workshop_name, ' 产能达成率低于 80%') AS alert_desc,
    0 AS is_resolved
FROM dws_db.dws_produce_day p
LEFT JOIN dwd_db.dim_workshop w ON p.workshop_id = w.workshop_id
WHERE p.stat_date BETWEEN '2025-10-01' AND '2026-06-30'
  AND p.plan_qty > 0
  AND p.actual_qty * 100.0 / p.plan_qty < 80
ORDER BY p.stat_date DESC
LIMIT 100;