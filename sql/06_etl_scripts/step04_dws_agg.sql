-- 先清空汇总表（全量重建；表名带库前缀，不依赖 USE 选择默认库）
TRUNCATE TABLE dws_db.dws_sale_day;
TRUNCATE TABLE dws_db.dws_sale_month;
TRUNCATE TABLE dws_db.dws_produce_day;
TRUNCATE TABLE dws_db.dws_stock_day;
TRUNCATE TABLE dws_db.dws_cost_month;
-- 1. 销售日汇总
-- 口径（对应说明书 7.1 营业收入定义）：剔除「已取消」「已作废」订单，只统计有效订单。
-- 原实现未剔除已取消订单，导致营收虚高约 20%。
-- 交付口径：delivery_cnt = 已交付订单数（delivery_date 不为空），
--           订单履约率 = delivery_ontime_cnt / delivery_cnt（按时交付 ÷ 已交付），
--           未发货订单不再计入分母（原实现用全部订单做分母，把 17 万未发货单算作"不按时"）。
INSERT INTO dws_db.dws_sale_day (stat_date, product_id, customer_id, region, order_cnt, order_amt, paid_amt, delivery_ontime_cnt, delivery_cnt, return_amt)
SELECT
    order_date AS stat_date,
    product_id,
    COALESCE(customer_id, 'UNKNOWN') AS customer_id,
    MAX(region) AS region,
    COUNT(*) AS order_cnt,
    SUM(order_amount) AS order_amt,
    SUM(CASE WHEN payment_date IS NOT NULL THEN order_amount ELSE 0 END) AS paid_amt,
    SUM(CASE WHEN delivery_date IS NOT NULL AND delivery_date <= order_date + INTERVAL 7 DAY THEN 1 ELSE 0 END) AS delivery_ontime_cnt,
    SUM(CASE WHEN delivery_date IS NOT NULL THEN 1 ELSE 0 END) AS delivery_cnt,
    SUM(CASE WHEN order_status = '已退货' THEN order_amount ELSE 0 END) AS return_amt
FROM dwd_db.dwd_sale_order_detail
WHERE order_status NOT IN ('已取消', '已作废')
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
-- 说明：oee_rate 列名的实际口径是「产能达成率 = 实际产量 / 计划产量」，
-- 真正的 OEE（时间开动率×性能开动率×合格品率）需用设备运行记录单独计算，见 dwd_equipment_runtime。
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

-- 4. 库存日汇总
-- 修正点：库存数量/金额必须取库存快照（dwd_stock_snapshot）的结存，
-- 原实现用出入库流水推导并直接写 0，导致库存健康看板全为 0。
-- 周转天数 = 当日库存金额 / 近 30 天日均出库金额（无出库记为 NULL）。
INSERT INTO dws_db.dws_stock_day (stat_date, material_id, warehouse_id, stock_qty, stock_amt, in_qty, out_qty, turnover_days)
SELECT
    s.snapshot_date AS stat_date,
    s.material_id,
    s.warehouse_id,
    s.stock_qty,
    s.stock_amount AS stock_amt,
    COALESCE(io.in_qty, 0) AS in_qty,
    COALESCE(io.out_qty, 0) AS out_qty,
    CASE WHEN o.avg_out_amt > 0 THEN ROUND(s.stock_amount / o.avg_out_amt, 2) END AS turnover_days
FROM dwd_db.dwd_stock_snapshot s
LEFT JOIN (
    SELECT
        io_date,
        material_id,
        warehouse_id,
        SUM(CASE WHEN io_type = 'IN' THEN io_qty ELSE 0 END) AS in_qty,
        SUM(CASE WHEN io_type = 'OUT' THEN io_qty ELSE 0 END) AS out_qty
    FROM dwd_db.dwd_stock_io_detail
    GROUP BY io_date, material_id, warehouse_id
) io ON io.io_date = s.snapshot_date AND io.material_id = s.material_id AND io.warehouse_id = s.warehouse_id
LEFT JOIN (
    SELECT
        material_id,
        warehouse_id,
        io_date,
        SUM(out_amt) OVER (
            PARTITION BY material_id, warehouse_id
            ORDER BY io_date
            RANGE BETWEEN INTERVAL 29 DAY PRECEDING AND CURRENT ROW
        ) / 30 AS avg_out_amt
    FROM (
        SELECT
            io_date,
            material_id,
            warehouse_id,
            SUM(CASE WHEN io_type = 'OUT' THEN io_amount ELSE 0 END) AS out_amt
        FROM dwd_db.dwd_stock_io_detail
        GROUP BY io_date, material_id, warehouse_id
    ) od
) o ON o.io_date = s.snapshot_date AND o.material_id = s.material_id AND o.warehouse_id = s.warehouse_id;

-- 5. 成本月汇总
-- cost_diff_rate = 单位成本环比差异率（对上月，%），原实现写死 0。
-- 上月单位成本由同一份 DWD 再聚合一次得到（不用临时表：脚本不选默认库，临时表会报 1046）。
INSERT INTO dws_db.dws_cost_month (stat_month, product_id, workshop_id, material_cost, labor_cost, mfg_cost, total_cost, unit_cost, cost_diff_rate)
SELECT
    c.stat_month,
    c.product_id,
    c.workshop_id,
    c.material_cost,
    c.labor_cost,
    c.mfg_cost,
    c.total_cost,
    ROUND(c.total_cost * 1.0 / NULLIF(c.prod_qty, 0), 2) AS unit_cost,
    CASE
        WHEN p.prev_qty > 0 AND p.prev_total_cost > 0
        THEN ROUND(
            (c.total_cost * 1.0 / NULLIF(c.prod_qty, 0)
             - p.prev_total_cost * 1.0 / NULLIF(p.prev_qty, 0))
            * 100.0 / NULLIF(p.prev_total_cost * 1.0 / NULLIF(p.prev_qty, 0), 0), 2)
    END AS cost_diff_rate
FROM (
    SELECT
        cost_month AS stat_month,
        COALESCE(c.product_id, 'UNKNOWN') AS product_id,
        COALESCE(c.workshop_id, 'UNKNOWN') AS workshop_id,
        SUM(material_cost) AS material_cost,
        SUM(labor_cost) AS labor_cost,
        SUM(mfg_cost) AS mfg_cost,
        SUM(total_cost) AS total_cost,
        SUM(w.actual_qty) AS prod_qty
    FROM dwd_db.dwd_cost_detail c
    LEFT JOIN dwd_db.dwd_produce_workorder_detail w USING (workorder_id)
    GROUP BY cost_month, COALESCE(c.product_id, 'UNKNOWN'), COALESCE(c.workshop_id, 'UNKNOWN')
) c
LEFT JOIN (
    SELECT
        cost_month AS stat_month,
        COALESCE(c.product_id, 'UNKNOWN') AS product_id,
        COALESCE(c.workshop_id, 'UNKNOWN') AS workshop_id,
        SUM(total_cost) AS prev_total_cost,
        SUM(w.actual_qty) AS prev_qty
    FROM dwd_db.dwd_cost_detail c
    LEFT JOIN dwd_db.dwd_produce_workorder_detail w USING (workorder_id)
    GROUP BY cost_month, COALESCE(c.product_id, 'UNKNOWN'), COALESCE(c.workshop_id, 'UNKNOWN')
) p
  ON p.product_id = c.product_id
 AND p.workshop_id = c.workshop_id
 AND p.stat_month = DATE_FORMAT(
        DATE_SUB(STR_TO_DATE(CONCAT(c.stat_month, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m');
