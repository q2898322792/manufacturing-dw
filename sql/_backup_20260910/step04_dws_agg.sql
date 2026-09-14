-- 先清空汇总表（全量重建；表名带库前缀，不依赖 USE 选择默认库）
TRUNCATE TABLE dws_db.dws_sale_day;
TRUNCATE TABLE dws_db.dws_sale_month;
TRUNCATE TABLE dws_db.dws_produce_day;
TRUNCATE TABLE dws_db.dws_stock_day;
TRUNCATE TABLE dws_db.dws_cost_month;

-- 1. 销售日汇总
INSERT INTO dws_db.dws_sale_day (stat_date, product_id, customer_id, region, order_cnt, order_amt, paid_amt, delivery_ontime_cnt, return_amt)
SELECT
    order_date AS stat_date,
    product_id,
    COALESCE(customer_id, 'UNKNOWN') AS customer_id,
    MAX(region) AS region,
    COUNT(*) AS order_cnt,
    SUM(order_amount) AS order_amt,
    SUM(CASE WHEN payment_date IS NOT NULL THEN order_amount ELSE 0 END) AS paid_amt,
    SUM(CASE WHEN delivery_date IS NOT NULL AND delivery_date <= order_date + INTERVAL 7 DAY THEN 1 ELSE 0 END) AS delivery_ontime_cnt,
    SUM(CASE WHEN order_status = '已退货' THEN order_amount ELSE 0 END) AS return_amt
FROM dwd_db.dwd_sale_order_detail
GROUP BY order_date, product_id, COALESCE(customer_id, 'UNKNOWN');

-- 2. 销售月汇总
INSERT INTO dws_db.dws_sale_month (stat_month, product_id, customer_id, region, order_cnt, order_amt, paid_amt, delivery_ontime_cnt, return_amt)
SELECT
    DATE_FORMAT(stat_date, '%Y-%m') AS stat_month,
    product_id,
    customer_id,
    MAX(region) AS region,
    SUM(order_cnt) AS order_cnt,
    SUM(order_amt) AS order_amt,
    SUM(paid_amt) AS paid_amt,
    SUM(delivery_ontime_cnt) AS delivery_ontime_cnt,
    SUM(return_amt) AS return_amt
FROM dws_db.dws_sale_day
GROUP BY DATE_FORMAT(stat_date, '%Y-%m'), product_id, customer_id;

-- 3. 生产日汇总
INSERT INTO dws_db.dws_produce_day (stat_date, workshop_id, product_id, plan_qty, actual_qty, qualified_qty, defect_qty, labor_hours, oee_rate)
SELECT
    plan_start_date AS stat_date,
    workshop_id,
    COALESCE(product_id, 'UNKNOWN') AS product_id,
    SUM(plan_qty) AS plan_qty,
    SUM(actual_qty) AS actual_qty,
    SUM(qualified_qty) AS qualified_qty,
    SUM(defect_qty) AS defect_qty,
    SUM(labor_hours) AS labor_hours,
    ROUND(SUM(actual_qty) * 100.0 / NULLIF(SUM(plan_qty), 0), 2) AS oee_rate
FROM dwd_db.dwd_produce_workorder_detail
GROUP BY plan_start_date, workshop_id, COALESCE(product_id, 'UNKNOWN');

-- 4. 库存日汇总（使用 dwd_stock_io_detail 替代缺失的 dwd_stock_snapshot）
INSERT INTO dws_db.dws_stock_day (stat_date, material_id, warehouse_id, stock_qty, stock_amt, in_qty, out_qty, turnover_days)
SELECT
    io_date AS stat_date,
    COALESCE(material_id, 'UNKNOWN') AS material_id,
    warehouse_id,
    0 AS stock_qty,
    0 AS stock_amt,
    SUM(CASE WHEN io_type = 'IN' THEN io_qty ELSE 0 END) AS in_qty,
    SUM(CASE WHEN io_type = 'OUT' THEN io_qty ELSE 0 END) AS out_qty,
    0 AS turnover_days
FROM dwd_db.dwd_stock_io_detail
GROUP BY io_date, material_id, warehouse_id;

-- 5. 成本月汇总
INSERT INTO dws_db.dws_cost_month (stat_month, product_id, workshop_id, material_cost, labor_cost, mfg_cost, total_cost, unit_cost, cost_diff_rate)
SELECT
    cost_month AS stat_month,
    COALESCE(c.product_id, 'UNKNOWN') AS product_id,
    COALESCE(c.workshop_id, 'UNKNOWN') AS workshop_id,
    SUM(material_cost) AS material_cost,
    SUM(labor_cost) AS labor_cost,
    SUM(mfg_cost) AS mfg_cost,
    SUM(total_cost) AS total_cost,
    ROUND(SUM(total_cost) * 1.0 / NULLIF(SUM(w.actual_qty), 0), 2) AS unit_cost,
    0 AS cost_diff_rate
FROM dwd_db.dwd_cost_detail c
LEFT JOIN dwd_db.dwd_produce_workorder_detail w USING (workorder_id)
GROUP BY cost_month, COALESCE(c.product_id, 'UNKNOWN'), COALESCE(c.workshop_id, 'UNKNOWN');