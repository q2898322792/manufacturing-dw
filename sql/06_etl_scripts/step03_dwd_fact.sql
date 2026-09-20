-- ============================================================
-- step03_dwd_fact.sql（事实层 · 按日增量版）
-- ============================================================
-- 策略：不再 TRUNCATE 全表，而是**只重算"受影响的日期区间"**：
--
--     区间 = [ max(DWD 已有该表日期) - @lookback 天 , max(ODS 该表日期) ]
--
--   · DWD 为空（首次 / 整表重建）时，@d1 自动退化为 ODS 的最小日期 → **等价于全量**
--   · 日常运行时只重算最近 @lookback 天，覆盖"迟到数据 + 状态变更"，历史分区不动
--
-- 相比原来的 TRUNCATE + 全量 INSERT，三个改进：
--   1. **增量**：日常只重算最近 @lookback 天，不再每天全表重灌
--   2. **原子性**：DELETE 是 DML，受事务保护 —— 顺带补上 §4.5 记录的
--      "TRUNCATE 隐式提交 → 中途失败留下空表" 的缺口（TRUNCATE 无法回滚，DELETE 可以）
--   3. **分区剪枝**：WHERE 带分区列，MySQL 只扫相关月度分区（见各表的 PARTITION BY）
--
-- @lookback 取 45 天：需大于"历史上出现过的最大缺口"（历史最大为 30 天）。
--   若确实存在更大的历史缺口，把 @lookback 调大，或先手工清表再跑一次（会退化为全量）。
-- ============================================================

SET @lookback = 45;

-- ------------------------------------------------------------
-- 6. 销售订单事实表（分区键 order_date）
-- 过滤条件：订单号不为空、状态不是已作废、金额大于0小于1000万
-- ------------------------------------------------------------
SET @d2 = (SELECT MAX(order_date) FROM ods_db.ods_erp_sale_order);
SET @d1 = COALESCE(
    (SELECT DATE_SUB(MAX(order_date), INTERVAL @lookback DAY) FROM dwd_db.dwd_sale_order_detail),
    (SELECT MIN(order_date) FROM ods_db.ods_erp_sale_order));
DELETE FROM dwd_db.dwd_sale_order_detail WHERE order_date BETWEEN @d1 AND @d2;
INSERT INTO dwd_db.dwd_sale_order_detail ( order_id, customer_id, product_id, order_date, order_amount, tax_amount, discount_amount, net_amount, order_status, delivery_date, payment_date, region, quantity ) SELECT
order_id,
customer_id,
product_id,
order_date,
order_amount,
tax_amount,
discount_amount,
net_amount,
order_status,
delivery_date,
payment_date,
region,
quantity
FROM
	ods_db.ods_erp_sale_order
WHERE
	order_date BETWEEN @d1 AND @d2
	AND order_id IS NOT NULL
	AND order_status != '已作废'
	AND order_amount > 0
	AND order_amount < 10000000;

-- ------------------------------------------------------------
-- 7. 生产工单事实表（分区键 plan_start_date）
-- 过滤条件：工单号不为空、实际产量不超过计划产量的2倍
-- ------------------------------------------------------------
SET @d2 = (SELECT MAX(plan_start_date) FROM ods_db.ods_mes_workorder);
SET @d1 = COALESCE(
    (SELECT DATE_SUB(MAX(plan_start_date), INTERVAL @lookback DAY) FROM dwd_db.dwd_produce_workorder_detail),
    (SELECT MIN(plan_start_date) FROM ods_db.ods_mes_workorder));
DELETE FROM dwd_db.dwd_produce_workorder_detail WHERE plan_start_date BETWEEN @d1 AND @d2;
INSERT INTO dwd_db.dwd_produce_workorder_detail (
	workorder_id,
	product_id,
	workshop_id,
	plan_qty,
	actual_qty,
	qualified_qty,
	defect_qty,
	defect_type,
	plan_start_date,
	plan_end_date,
	actual_start_date,
	actual_end_date,
	workorder_status,
	labor_hours,
	material_loss
) SELECT
workorder_id,
product_id,
workshop_id,
plan_qty,
actual_qty,
qualified_qty,
defect_qty,
defect_type,
plan_start_date,
plan_end_date,
actual_start_date,
actual_end_date,
workorder_status,
labor_hours,
material_loss
FROM
	ods_db.ods_mes_workorder
WHERE
	plan_start_date BETWEEN @d1 AND @d2
	AND workorder_id IS NOT NULL
	AND actual_qty <= plan_qty * 2;

-- ------------------------------------------------------------
-- 8. 出入库明细事实表（分区键 io_date）
-- 过滤条件：记录ID不为空、数量大于0
-- ------------------------------------------------------------
SET @d2 = (SELECT MAX(io_date) FROM ods_db.ods_wms_stock_io);
SET @d1 = COALESCE(
    (SELECT DATE_SUB(MAX(io_date), INTERVAL @lookback DAY) FROM dwd_db.dwd_stock_io_detail),
    (SELECT MIN(io_date) FROM ods_db.ods_wms_stock_io));
DELETE FROM dwd_db.dwd_stock_io_detail WHERE io_date BETWEEN @d1 AND @d2;
INSERT INTO dwd_db.dwd_stock_io_detail ( io_id, material_id, warehouse_id, io_type, io_qty, io_amount, unit_price, io_date, supplier_id, workorder_id, order_id ) SELECT
io_id,
material_id,
warehouse_id,
io_type,
io_qty,
io_amount,
unit_price,
io_date,
supplier_id,
workorder_id,
order_id
FROM
	ods_db.ods_wms_stock_io
WHERE
	io_date BETWEEN @d1 AND @d2
	AND io_id IS NOT NULL
	AND io_qty > 0;

-- ------------------------------------------------------------
-- 9. 成本明细事实表（分区键 cost_month，是 'YYYY-MM' 字符串）
-- 过滤条件：凭证ID不为空、总成本大于0
-- 注意：业务日期列是 cost_month（字符串），不能直接减天数，
--       先把 'YYYY-MM' 补成 'YYYY-MM-01' 再减 @lookback 天，最后格式化回 'YYYY-MM'。
-- ------------------------------------------------------------
SET @m2 = (SELECT MAX(cost_month) FROM ods_db.ods_erp_cost_voucher);
SET @m1 = COALESCE(
    (SELECT DATE_FORMAT(DATE_SUB(CONCAT(MAX(cost_month), '-01'), INTERVAL @lookback DAY), '%Y-%m')
       FROM dwd_db.dwd_cost_detail),
    (SELECT MIN(cost_month) FROM ods_db.ods_erp_cost_voucher));
DELETE FROM dwd_db.dwd_cost_detail WHERE cost_month BETWEEN @m1 AND @m2;
INSERT INTO dwd_db.dwd_cost_detail ( voucher_id, product_id, workshop_id, workorder_id, material_cost, labor_cost, mfg_cost, total_cost, cost_month ) SELECT
voucher_id,
product_id,
workshop_id,
workorder_id,
material_cost,
labor_cost,
mfg_cost,
total_cost,
cost_month
FROM
	ods_db.ods_erp_cost_voucher
WHERE
	cost_month BETWEEN @m1 AND @m2
	AND voucher_id IS NOT NULL
	AND total_cost > 0;

-- ------------------------------------------------------------
-- 10. 设备运行记录事实表（分区键 record_date）
-- 过滤条件：记录ID不为空、运行时间大于0
-- ------------------------------------------------------------
SET @d2 = (SELECT MAX(record_date) FROM ods_db.ods_mes_equipment_runtime);
SET @d1 = COALESCE(
    (SELECT DATE_SUB(MAX(record_date), INTERVAL @lookback DAY) FROM dwd_db.dwd_equipment_runtime),
    (SELECT MIN(record_date) FROM ods_db.ods_mes_equipment_runtime));
DELETE FROM dwd_db.dwd_equipment_runtime WHERE record_date BETWEEN @d1 AND @d2;
INSERT INTO dwd_db.dwd_equipment_runtime ( record_id, equipment_id, workshop_id, record_date, runtime_min, idle_min, fault_min, maintain_min, total_min ) SELECT
record_id,
equipment_id,
workshop_id,
record_date,
runtime_min,
idle_min,
fault_min,
maintain_min,
total_min
FROM
	ods_db.ods_mes_equipment_runtime
WHERE
	record_date BETWEEN @d1 AND @d2
	AND record_id IS NOT NULL
	AND runtime_min > 0;

-- ------------------------------------------------------------
-- 11. 库存快照事实表（分区键 snapshot_date）
-- 来源 WMS 库存快照（每日每物料每仓库一行），是库存数量/金额的唯一权威来源，
-- 不能再用出入库流水推导（流水只有进出量，没有结存）。
-- ------------------------------------------------------------
SET @d2 = (SELECT MAX(snapshot_date) FROM ods_db.ods_wms_stock_snapshot);
SET @d1 = COALESCE(
    (SELECT DATE_SUB(MAX(snapshot_date), INTERVAL @lookback DAY) FROM dwd_db.dwd_stock_snapshot),
    (SELECT MIN(snapshot_date) FROM ods_db.ods_wms_stock_snapshot));
DELETE FROM dwd_db.dwd_stock_snapshot WHERE snapshot_date BETWEEN @d1 AND @d2;
INSERT INTO dwd_db.dwd_stock_snapshot ( snapshot_date, material_id, warehouse_id, stock_qty, stock_amount ) SELECT
snapshot_date,
material_id,
warehouse_id,
SUM( stock_qty ) AS stock_qty,
SUM( stock_amount ) AS stock_amount
FROM
	ods_db.ods_wms_stock_snapshot
WHERE
	snapshot_date BETWEEN @d1 AND @d2
	AND snapshot_id IS NOT NULL
	AND material_id IS NOT NULL
	AND snapshot_date IS NOT NULL
GROUP BY
	snapshot_date,
	material_id,
	warehouse_id;
