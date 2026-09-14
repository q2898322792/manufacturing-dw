-- 先清空应用层报表表（全量重建；表名带库前缀，不依赖 USE 选择默认库）
TRUNCATE TABLE ads_db.ads_boss_dashboard;
TRUNCATE TABLE ads_db.ads_sale_analysis;
TRUNCATE TABLE ads_db.ads_produce_monitor;
TRUNCATE TABLE ads_db.ads_stock_health;
TRUNCATE TABLE ads_db.ads_cost_profit;
TRUNCATE TABLE ads_db.ads_alert_warning;
-- ============================================================
-- 口径说明（V2.1 修正版）
--   1) 所有指标均为计算得出，不再有任何写死常量（原版本的 15% 利润率、
--      45 天周转、45/25/30 成本占比、23.08% 毛利率、'尺寸偏差' 等已全部移除）。
--   2) 营收口径：剔除「已取消」「已作废」订单（见 step04 的 dws_sale_day）。
--   3) 时间范围：不再写死 2025-10-01 ~ 2026-06-30，全部按库内最新数据动态计算。
--   4) 快照类表（大屏/库存/预警）按业务日期逐日/取最新日生成，支持趋势与时间筛选。
-- ============================================================

-- 6. 经营总览大屏（逐日快照，每日一行）
-- 利润说明：源数据没有「期间费用」，因此 total_profit 为毛利口径
--          （营收 - 已售产品成本），已售产品成本 = 当月产品单位成本 × 当月销量。
--          当月无成本凭证时利润留空（NULL），不再用固定比例编造。
INSERT INTO ads_db.ads_boss_dashboard (stat_date, total_revenue, total_profit, profit_rate, capacity_achieved, inventory_turnover, order_fulfill_rate, material_cost_ratio, labor_cost_ratio, mfg_cost_ratio)
SELECT
    d.stat_date,
    ROUND(COALESCE(s.order_amt, 0), 2) AS total_revenue,
    CASE WHEN cr.sold_cost_ratio IS NULL THEN NULL
         ELSE ROUND(COALESCE(s.order_amt, 0) * (1 - cr.sold_cost_ratio), 2) END AS total_profit,
    CASE WHEN cr.sold_cost_ratio IS NULL THEN NULL
         ELSE ROUND((1 - cr.sold_cost_ratio) * 100, 2) END AS profit_rate,
    p.capacity_achieved,
    CASE WHEN o.avg_out_amt > 0 THEN ROUND(st.stock_amt / o.avg_out_amt, 2) END AS inventory_turnover,
    ROUND(s.delivery_ontime_cnt * 100.0 / NULLIF(s.delivery_cnt, 0), 2) AS order_fulfill_rate,
    cm.material_cost_ratio,
    cm.labor_cost_ratio,
    cm.mfg_cost_ratio
FROM (
    SELECT stat_date FROM dws_db.dws_sale_day
    UNION
    SELECT stat_date FROM dws_db.dws_produce_day
) d
LEFT JOIN (
    SELECT
        stat_date,
        SUM(order_cnt) AS order_cnt,
        SUM(order_amt) AS order_amt,
        SUM(delivery_ontime_cnt) AS delivery_ontime_cnt,
        SUM(delivery_cnt) AS delivery_cnt
    FROM dws_db.dws_sale_day
    GROUP BY stat_date
) s ON s.stat_date = d.stat_date
LEFT JOIN (
    SELECT
        stat_date,
        ROUND(SUM(actual_qty) * 100.0 / NULLIF(SUM(plan_qty), 0), 2) AS capacity_achieved
    FROM dws_db.dws_produce_day
    GROUP BY stat_date
) p ON p.stat_date = d.stat_date
LEFT JOIN (
    SELECT stat_date, SUM(stock_amt) AS stock_amt
    FROM dws_db.dws_stock_day
    GROUP BY stat_date
) st ON st.stat_date = d.stat_date
LEFT JOIN (
    SELECT
        io_date,
        SUM(out_amt) OVER (
            ORDER BY io_date
            RANGE BETWEEN INTERVAL 29 DAY PRECEDING AND CURRENT ROW
        ) / 30 AS avg_out_amt
    FROM (
        SELECT
            io_date,
            SUM(CASE WHEN io_type = 'OUT' THEN io_amount ELSE 0 END) AS out_amt
        FROM dwd_db.dwd_stock_io_detail
        GROUP BY io_date
    ) od
) o ON o.io_date = d.stat_date
LEFT JOIN (
    -- 当月已售产品成本率 = Σ(产品当月单位成本 × 当月销量) / 当月营收
    SELECT
        sd.stat_month,
        SUM(sd.qty * pc.unit_cost) / NULLIF(SUM(sd.revenue), 0) AS sold_cost_ratio
    FROM (
        SELECT
            DATE_FORMAT(order_date, '%Y-%m') AS stat_month,
            product_id,
            SUM(quantity) AS qty,
            SUM(order_amount) AS revenue
        FROM dwd_db.dwd_sale_order_detail
        WHERE order_status NOT IN ('已取消', '已作废')
        GROUP BY DATE_FORMAT(order_date, '%Y-%m'), product_id
    ) sd
    LEFT JOIN (
        SELECT
            c.cost_month AS stat_month,
            c.product_id,
            SUM(c.total_cost) / NULLIF(SUM(w.actual_qty), 0) AS unit_cost
        FROM dwd_db.dwd_cost_detail c
        LEFT JOIN dwd_db.dwd_produce_workorder_detail w USING (workorder_id)
        GROUP BY c.cost_month, c.product_id
    ) pc ON pc.stat_month = sd.stat_month AND pc.product_id = sd.product_id
    GROUP BY sd.stat_month
) cr ON cr.stat_month = DATE_FORMAT(d.stat_date, '%Y-%m')
LEFT JOIN (
    -- 当月成本结构占比（物料/人工/制造费用 ÷ 当月总成本）
    SELECT
        stat_month,
        ROUND(SUM(material_cost) * 100.0 / NULLIF(SUM(total_cost), 0), 2) AS material_cost_ratio,
        ROUND(SUM(labor_cost) * 100.0 / NULLIF(SUM(total_cost), 0), 2) AS labor_cost_ratio,
        ROUND(SUM(mfg_cost) * 100.0 / NULLIF(SUM(total_cost), 0), 2) AS mfg_cost_ratio
    FROM dws_db.dws_cost_month
    GROUP BY stat_month
) cm ON cm.stat_month = DATE_FORMAT(d.stat_date, '%Y-%m');

-- 7. 销售分析报表（全量日期，不写死区间）
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
    -- 交付及时率 = 按时交付订单数 ÷ 已交付订单数（未发货订单不计入分母）
    ROUND(s.delivery_ontime_cnt * 100.0 / NULLIF(s.delivery_cnt, 0), 2) AS delivery_ontime_rate
FROM dws_db.dws_sale_day s
LEFT JOIN dwd_db.dim_customer c ON s.customer_id = c.customer_id
LEFT JOIN dwd_db.dim_product p ON s.product_id = p.product_id;

-- 8. 生产监控报表（全量日期）
-- 产量类字段（计划/实际/良品/不良）取自 dws_produce_day 的整组汇总，保证与 DWD/DWS 口径完全一致；
-- defect_type 取该日该车间该产品「不良数量最多」的真实类型（源表 defect_type 本来就有
-- 尺寸偏差/外观缺陷/性能失效/其他 4 类，原实现硬编码成 '尺寸偏差'，导致不良类型分布只有一根柱子）。
INSERT INTO ads_db.ads_produce_monitor (stat_date, workshop_id, workshop_name, product_id, product_name, plan_qty, actual_qty, qualified_qty, defect_qty, defect_type, capacity_achieved, qualified_rate)
SELECT
    d.stat_date,
    d.workshop_id,
    w.workshop_name,
    d.product_id,
    pr.product_name,
    d.plan_qty,
    d.actual_qty,
    d.qualified_qty,
    d.defect_qty,
    COALESCE(dt.defect_type, '未标注') AS defect_type,
    ROUND(d.actual_qty * 100.0 / NULLIF(d.plan_qty, 0), 2) AS capacity_achieved,
    ROUND(d.qualified_qty * 100.0 / NULLIF(d.actual_qty, 0), 2) AS qualified_rate
FROM dws_db.dws_produce_day d
LEFT JOIN (
    SELECT stat_date, workshop_id, product_id, defect_type
    FROM (
        SELECT
            plan_start_date AS stat_date,
            workshop_id,
            COALESCE(product_id, 'UNKNOWN') AS product_id,
            COALESCE(defect_type, '未标注') AS defect_type,
            ROW_NUMBER() OVER (
                PARTITION BY plan_start_date, workshop_id, COALESCE(product_id, 'UNKNOWN')
                ORDER BY SUM(defect_qty) DESC, COALESCE(defect_type, '未标注')
            ) AS rn
        FROM dwd_db.dwd_produce_workorder_detail
        GROUP BY plan_start_date, workshop_id, COALESCE(product_id, 'UNKNOWN'), COALESCE(defect_type, '未标注')
    ) g
    WHERE g.rn = 1
) dt
  ON dt.stat_date = d.stat_date
 AND dt.workshop_id = d.workshop_id
 AND dt.product_id = d.product_id
LEFT JOIN dwd_db.dim_workshop w ON d.workshop_id = w.workshop_id
LEFT JOIN dwd_db.dim_product pr ON d.product_id = pr.product_id;

-- 9. 库存健康度报表（最新「可完整计算」快照日全量物料，不再 LIMIT 100，保证呆滞占比算得准）
-- 基准日：取最新一天「能算出周转天数」的快照日，保证库存数量/金额/周转天数在同一基准日。
-- 说明：当前出入库流水只到 2026-06-29，而库存快照到 2026-07-31，故基准日落在 6-29；
--      等增量脚本补齐 7 月以后的出入库流水，基准日会自动前移，无需改 SQL。
-- 呆滞判定：周转天数 > 90 天，或近 30 天完全没有出库（周转天数为 NULL）
INSERT INTO ads_db.ads_stock_health (stat_date, material_id, material_name, warehouse_id, stock_qty, stock_amt, turnover_days, is_slow_moving)
SELECT
    s.stat_date,
    s.material_id,
    COALESCE(m.material_name, '未知物料') AS material_name,
    s.warehouse_id,
    s.stock_qty,
    s.stock_amt,
    s.turnover_days,
    CASE WHEN s.turnover_days IS NULL OR s.turnover_days > 90 THEN 1 ELSE 0 END AS is_slow_moving
FROM dws_db.dws_stock_day s
LEFT JOIN dwd_db.dim_material m ON s.material_id = m.material_id
WHERE s.stat_date = (SELECT MAX(stat_date) FROM dws_db.dws_stock_day WHERE turnover_days IS NOT NULL);

-- 10. 成本利润分析（全量月份，不再只留最近 3 个月）
-- 销售均价取真实售价（当月该产品营收 ÷ 销量），不再用「单位成本 × 1.3」编造
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
    ROUND(sp.sale_price, 2) AS sale_price,
    ROUND(sp.sale_price - c.unit_cost, 2) AS unit_profit,
    ROUND((sp.sale_price - c.unit_cost) * 100.0 / NULLIF(sp.sale_price, 0), 2) AS profit_rate
FROM dws_db.dws_cost_month c
LEFT JOIN dwd_db.dim_product p ON c.product_id = p.product_id
LEFT JOIN dwd_db.dim_workshop w ON c.workshop_id = w.workshop_id
LEFT JOIN (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m') AS stat_month,
        product_id,
        SUM(order_amount) / NULLIF(SUM(quantity), 0) AS sale_price
    FROM dwd_db.dwd_sale_order_detail
    WHERE order_status NOT IN ('已取消', '已作废')
    GROUP BY DATE_FORMAT(order_date, '%Y-%m'), product_id
) sp ON sp.stat_month = c.stat_month AND sp.product_id = c.product_id;

-- 11. 异常预警清单（五类：营收缺口 / 产能不足 / 库存积压 / 不良超标 / 回款滞后）

-- 11.1 产能不足：最近一个有完整数据的业务日，车间产能达成率 < 80%
INSERT INTO ads_db.ads_alert_warning (alert_id, alert_date, alert_type, alert_level, target_name, target_id, current_value, threshold_value, alert_desc, is_resolved)
SELECT
    CONCAT('AL-CAP-', LPAD(ROW_NUMBER() OVER (ORDER BY t.r ASC), 4, '0')) AS alert_id,
    t.stat_date,
    '产能不足',
    CASE WHEN t.r < 60 THEN '高' WHEN t.r < 75 THEN '中' ELSE '低' END,
    COALESCE(w.workshop_name, t.workshop_id),
    t.workshop_id,
    CONCAT(ROUND(t.r, 2), '%'),
    '80%',
    CONCAT(COALESCE(w.workshop_name, t.workshop_id), ' 当日产能达成率 ', ROUND(t.r, 2), '%，低于 80% 标准'),
    0
FROM (
    SELECT
        stat_date,
        workshop_id,
        SUM(actual_qty) * 100.0 / NULLIF(SUM(plan_qty), 0) AS r
    FROM dws_db.dws_produce_day
    WHERE stat_date = (
        SELECT MAX(stat_date) FROM (
            SELECT stat_date FROM dws_db.dws_produce_day GROUP BY stat_date HAVING COUNT(*) >= 20
        ) biz
    )
    GROUP BY stat_date, workshop_id
) t
LEFT JOIN dwd_db.dim_workshop w ON t.workshop_id = w.workshop_id
WHERE t.r < 80;

-- 11.2 不良超标：同一业务日，车间良品率 < 95%
INSERT INTO ads_db.ads_alert_warning (alert_id, alert_date, alert_type, alert_level, target_name, target_id, current_value, threshold_value, alert_desc, is_resolved)
SELECT
    CONCAT('AL-DEF-', LPAD(ROW_NUMBER() OVER (ORDER BY t.q ASC), 4, '0')) AS alert_id,
    t.stat_date,
    '不良超标',
    CASE WHEN t.q < 90 THEN '高' WHEN t.q < 93 THEN '中' ELSE '低' END,
    COALESCE(w.workshop_name, t.workshop_id),
    t.workshop_id,
    CONCAT(ROUND(t.q, 2), '%'),
    '95%',
    CONCAT(COALESCE(w.workshop_name, t.workshop_id), ' 当日良品率 ', ROUND(t.q, 2), '%，低于 95% 标准'),
    0
FROM (
    SELECT
        stat_date,
        workshop_id,
        SUM(qualified_qty) * 100.0 / NULLIF(SUM(actual_qty), 0) AS q
    FROM dws_db.dws_produce_day
    WHERE stat_date = (
        SELECT MAX(stat_date) FROM (
            SELECT stat_date FROM dws_db.dws_produce_day GROUP BY stat_date HAVING COUNT(*) >= 20
        ) biz
    )
    GROUP BY stat_date, workshop_id
) t
LEFT JOIN dwd_db.dim_workshop w ON t.workshop_id = w.workshop_id
WHERE t.q < 95;

-- 11.3 库存积压：与库存健康度同一基准日，周转天数 > 90 天或近 30 天无出库（按库存金额取前 50）
INSERT INTO ads_db.ads_alert_warning (alert_id, alert_date, alert_type, alert_level, target_name, target_id, current_value, threshold_value, alert_desc, is_resolved)
SELECT
    CONCAT('AL-STK-', LPAD(ROW_NUMBER() OVER (ORDER BY s.stock_amt DESC), 4, '0')) AS alert_id,
    s.stat_date,
    '库存积压',
    CASE WHEN s.turnover_days IS NULL OR s.turnover_days > 180 THEN '高'
         WHEN s.turnover_days > 120 THEN '中' ELSE '低' END,
    COALESCE(m.material_name, s.material_id),
    s.material_id,
    CASE WHEN s.turnover_days IS NULL THEN '近30天无出库' ELSE CONCAT(ROUND(s.turnover_days, 2), '天') END,
    '90天',
    CONCAT(
        COALESCE(m.material_name, s.material_id), ' 在 ', s.warehouse_id, ' 库存 ', s.stock_qty,
        ' 件 / ', ROUND(s.stock_amt, 2), ' 元，',
        CASE WHEN s.turnover_days IS NULL THEN '近 30 天无出库记录' ELSE CONCAT('周转天数 ', ROUND(s.turnover_days, 2), ' 天') END,
        '，超过 90 天呆滞标准'
    ),
    0
FROM dws_db.dws_stock_day s
LEFT JOIN dwd_db.dim_material m ON s.material_id = m.material_id
WHERE s.stat_date = (SELECT MAX(stat_date) FROM dws_db.dws_stock_day WHERE turnover_days IS NOT NULL)
  AND (s.turnover_days IS NULL OR s.turnover_days > 90)
ORDER BY s.stock_amt DESC
LIMIT 50;

-- 11.4 营收缺口：最近一个完整月（当月有销售的天数 ≥ 20 天）
--      口径 = 「已取消订单金额」占「当月下单金额（含取消）」≥ 15% 的产品。
--      说明：模拟数据里各产品营收同涨同跌（产品/客户/区域三级环比下滑均为 0 个），
--            用「营收环比下滑」口径会恒为空，因此采用「取消订单造成的营收缺口」；
--            若后续补充月度目标表，可改为「实际营收 < 目标 × 80%」。
INSERT INTO ads_db.ads_alert_warning (alert_id, alert_date, alert_type, alert_level, target_name, target_id, current_value, threshold_value, alert_desc, is_resolved)
SELECT
    CONCAT('AL-REV-', LPAD(ROW_NUMBER() OVER (ORDER BY t.gap_amt DESC), 4, '0')) AS alert_id,
    DATE(CONCAT(t.stat_month, '-01')),
    '营收缺口',
    CASE WHEN t.cancel_rate >= 30 THEN '高' WHEN t.cancel_rate >= 20 THEN '中' ELSE '低' END,
    COALESCE(p.product_name, t.product_id),
    t.product_id,
    CONCAT(ROUND(t.gap_amt, 2), ' 元'),
    '取消率 15%',
    CONCAT(
        COALESCE(p.product_name, t.product_id), ' ', t.stat_month, ' 取消订单金额 ', ROUND(t.gap_amt, 2),
        ' 元，占当月下单金额 ', ROUND(t.cancel_rate, 2), '%（下单 ',
        ROUND(t.all_amt, 2), ' 元），形成营收缺口'
    ),
    0
FROM (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m') AS stat_month,
        product_id,
        SUM(CASE WHEN order_status = '已取消' THEN order_amount ELSE 0 END) AS gap_amt,
        SUM(order_amount) AS all_amt,
        SUM(CASE WHEN order_status = '已取消' THEN order_amount ELSE 0 END) * 100.0
            / NULLIF(SUM(order_amount), 0) AS cancel_rate
    FROM dwd_db.dwd_sale_order_detail
    WHERE order_status <> '已作废'
      AND DATE_FORMAT(order_date, '%Y-%m') = (
        SELECT stat_month FROM (
            SELECT DATE_FORMAT(stat_date, '%Y-%m') AS stat_month, COUNT(DISTINCT stat_date) AS d
            FROM dws_db.dws_sale_day
            GROUP BY DATE_FORMAT(stat_date, '%Y-%m')
            HAVING d >= 20
            ORDER BY stat_month DESC
            LIMIT 1
        ) m
      )
    GROUP BY DATE_FORMAT(order_date, '%Y-%m'), product_id
) t
LEFT JOIN dwd_db.dim_product p ON t.product_id = p.product_id
WHERE t.cancel_rate >= 15
ORDER BY t.gap_amt DESC
LIMIT 30;

-- 11.5 回款滞后：已发货/已完成但发货超过 30 天仍未回款，按客户汇总取前 30
INSERT INTO ads_db.ads_alert_warning (alert_id, alert_date, alert_type, alert_level, target_name, target_id, current_value, threshold_value, alert_desc, is_resolved)
SELECT
    CONCAT('AL-PAY-', LPAD(ROW_NUMBER() OVER (ORDER BY t.amt DESC), 4, '0')) AS alert_id,
    CURDATE(),
    '回款滞后',
    CASE WHEN t.max_overdue >= 90 THEN '高' WHEN t.max_overdue >= 60 THEN '中' ELSE '低' END,
    COALESCE(c.customer_name, t.customer_id),
    t.customer_id,
    CONCAT(ROUND(t.amt, 2), ' 元'),
    '30天',
    CONCAT(
        COALESCE(c.customer_name, t.customer_id), ' 有 ', t.cnt, ' 笔订单发货后超过 30 天未回款，合计 ',
        ROUND(t.amt, 2), ' 元，最长已逾期 ', t.max_overdue, ' 天'
    ),
    0
FROM (
    SELECT
        customer_id,
        COUNT(*) AS cnt,
        SUM(order_amount) AS amt,
        MAX(DATEDIFF(CURDATE(), delivery_date)) AS max_overdue
    FROM dwd_db.dwd_sale_order_detail
    WHERE payment_date IS NULL
      AND delivery_date IS NOT NULL
      AND order_status NOT IN ('已取消', '已作废')
      AND delivery_date <= CURDATE() - INTERVAL 30 DAY
    GROUP BY customer_id
) t
LEFT JOIN dwd_db.dim_customer c ON t.customer_id = c.customer_id
ORDER BY t.amt DESC
LIMIT 30;
