-- ============================================================
-- step03_dwd_fact.sql（事实层 · 按分区增量版）
-- ============================================================
-- 策略：**按整月分区重算**，而不是逐行 DELETE。
--
--   重算范围 = [ODS 最大业务日期所在月的前一个月, ODS 最大业务日期所在月]（2 个整月）
--   清理方式 = ALTER TABLE ... TRUNCATE PARTITION pA, pB   （秒级，直接丢弃分区数据）
--   写入方式 = INSERT ... SELECT ... WHERE <业务日期> BETWEEN <上月初> AND <ODS 最大日期>
--
-- 为什么从 DELETE 换成 TRUNCATE PARTITION：
--   上一版用 `DELETE ... WHERE <日期> BETWEEN @d1 AND @d2`，实测增量 295.7 秒，
--   其中 **DELETE 约 43 万行花了 ~151 秒** —— 逐行标记删除 + 维护 13 棵分区索引 + 写 undo/binlog，
--   比 INSERT 本身还贵。TRUNCATE PARTITION 是元数据级操作，秒级完成。
--
-- 两种模式（用 @dwd_max 是否为空自动判断，无需人工切换）：
--   · 首次 / 整表重建（DWD 该表为空）→ TRUNCATE TABLE + 全量 INSERT
--   · 日常增量（DWD 有数据）        → TRUNCATE PARTITION 2 个 + 该区间 INSERT
--
-- ⚠️ 原子性取舍（必须知道）：TRUNCATE PARTITION 是 **DDL，隐式提交、不可回滚**。
--    若紧接着的 INSERT 失败，那 2 个分区会暂时为空 —— **重跑本脚本即可恢复**（幂等）。
--    要彻底解决原子性，下一步可改成 `EXCHANGE PARTITION`（把算好的临时表原子换入分区），见 §7。
--
-- ⚠️ 前置依赖：分区必须已存在。`maintain_partitions.py` 在每轮 ETL 前自动补齐，
--    且建表脚本预建到 2026-12，所以正常情况下 pYYYYMM 一定存在。
-- ============================================================

-- ------------------------------------------------------------
-- 6. 销售订单事实表（分区键 order_date）
-- 过滤条件：订单号不为空、状态不是已作废、金额大于0小于1000万
-- ------------------------------------------------------------
SET @ods_max = (SELECT MAX(order_date) FROM ods_db.ods_erp_sale_order);
SET @dwd_max = (SELECT MAX(order_date) FROM dwd_db.dwd_sale_order_detail);
SET @p1 = CONCAT('p', DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y%m'));
SET @p2 = CONCAT('p', DATE_FORMAT(@ods_max, '%Y%m'));
SET @sql = IF(@dwd_max IS NULL,
    'TRUNCATE TABLE dwd_db.dwd_sale_order_detail',
    CONCAT('ALTER TABLE dwd_db.dwd_sale_order_detail TRUNCATE PARTITION ', @p1, ',', @p2));
PREPARE st FROM @sql;
EXECUTE st;
DEALLOCATE PREPARE st;
SET @d1 = IF(@dwd_max IS NULL,
    (SELECT MIN(order_date) FROM ods_db.ods_erp_sale_order),
    DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y-%m-01'));
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
	order_date BETWEEN @d1 AND @ods_max
	AND order_id IS NOT NULL
	AND order_status != '已作废'
	AND order_amount > 0
	AND order_amount < 10000000;

-- ------------------------------------------------------------
-- 7. 生产工单事实表（分区键 plan_start_date）
-- 过滤条件：工单号不为空、实际产量不超过计划产量的2倍
-- ------------------------------------------------------------
SET @ods_max = (SELECT MAX(plan_start_date) FROM ods_db.ods_mes_workorder);
SET @dwd_max = (SELECT MAX(plan_start_date) FROM dwd_db.dwd_produce_workorder_detail);
SET @p1 = CONCAT('p', DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y%m'));
SET @p2 = CONCAT('p', DATE_FORMAT(@ods_max, '%Y%m'));
SET @sql = IF(@dwd_max IS NULL,
    'TRUNCATE TABLE dwd_db.dwd_produce_workorder_detail',
    CONCAT('ALTER TABLE dwd_db.dwd_produce_workorder_detail TRUNCATE PARTITION ', @p1, ',', @p2));
PREPARE st FROM @sql;
EXECUTE st;
DEALLOCATE PREPARE st;
SET @d1 = IF(@dwd_max IS NULL,
    (SELECT MIN(plan_start_date) FROM ods_db.ods_mes_workorder),
    DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y-%m-01'));
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
	plan_start_date BETWEEN @d1 AND @ods_max
	AND workorder_id IS NOT NULL
	AND actual_qty <= plan_qty * 2;

-- ------------------------------------------------------------
-- 8. 出入库明细事实表（分区键 io_date）
-- 过滤条件：记录ID不为空、数量大于0
-- ------------------------------------------------------------
SET @ods_max = (SELECT MAX(io_date) FROM ods_db.ods_wms_stock_io);
SET @dwd_max = (SELECT MAX(io_date) FROM dwd_db.dwd_stock_io_detail);
SET @p1 = CONCAT('p', DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y%m'));
SET @p2 = CONCAT('p', DATE_FORMAT(@ods_max, '%Y%m'));
SET @sql = IF(@dwd_max IS NULL,
    'TRUNCATE TABLE dwd_db.dwd_stock_io_detail',
    CONCAT('ALTER TABLE dwd_db.dwd_stock_io_detail TRUNCATE PARTITION ', @p1, ',', @p2));
PREPARE st FROM @sql;
EXECUTE st;
DEALLOCATE PREPARE st;
SET @d1 = IF(@dwd_max IS NULL,
    (SELECT MIN(io_date) FROM ods_db.ods_wms_stock_io),
    DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y-%m-01'));
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
	io_date BETWEEN @d1 AND @ods_max
	AND io_id IS NOT NULL
	AND io_qty > 0;

-- ------------------------------------------------------------
-- 9. 成本明细事实表（分区键 cost_month，是 'YYYY-MM' 字符串）
-- 过滤条件：凭证ID不为空、总成本大于0
-- 注意：业务日期列是字符串，重算范围取最近 2 个 cost_month。
-- ------------------------------------------------------------
SET @ods_max_m = (SELECT MAX(cost_month) FROM ods_db.ods_erp_cost_voucher);
SET @dwd_max_m = (SELECT MAX(cost_month) FROM dwd_db.dwd_cost_detail);
SET @p1 = CONCAT('p', REPLACE(DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@ods_max_m, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m'), '-', ''));
SET @p2 = CONCAT('p', REPLACE(@ods_max_m, '-', ''));
SET @sql = IF(@dwd_max_m IS NULL,
    'TRUNCATE TABLE dwd_db.dwd_cost_detail',
    CONCAT('ALTER TABLE dwd_db.dwd_cost_detail TRUNCATE PARTITION ', @p1, ',', @p2));
PREPARE st FROM @sql;
EXECUTE st;
DEALLOCATE PREPARE st;
SET @m1 = IF(@dwd_max_m IS NULL,
    (SELECT MIN(cost_month) FROM ods_db.ods_erp_cost_voucher),
    DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(@ods_max_m, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m'));
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
	cost_month BETWEEN @m1 AND @ods_max_m
	AND voucher_id IS NOT NULL
	AND total_cost > 0;

-- ------------------------------------------------------------
-- 10. 设备运行记录事实表（分区键 record_date）
-- 过滤条件：记录ID不为空、运行时间大于0
-- ------------------------------------------------------------
SET @ods_max = (SELECT MAX(record_date) FROM ods_db.ods_mes_equipment_runtime);
SET @dwd_max = (SELECT MAX(record_date) FROM dwd_db.dwd_equipment_runtime);
SET @p1 = CONCAT('p', DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y%m'));
SET @p2 = CONCAT('p', DATE_FORMAT(@ods_max, '%Y%m'));
SET @sql = IF(@dwd_max IS NULL,
    'TRUNCATE TABLE dwd_db.dwd_equipment_runtime',
    CONCAT('ALTER TABLE dwd_db.dwd_equipment_runtime TRUNCATE PARTITION ', @p1, ',', @p2));
PREPARE st FROM @sql;
EXECUTE st;
DEALLOCATE PREPARE st;
SET @d1 = IF(@dwd_max IS NULL,
    (SELECT MIN(record_date) FROM ods_db.ods_mes_equipment_runtime),
    DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y-%m-01'));
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
	record_date BETWEEN @d1 AND @ods_max
	AND record_id IS NOT NULL
	AND runtime_min > 0;

-- ------------------------------------------------------------
-- 11. 库存快照事实表（分区键 snapshot_date）
-- 来源 WMS 库存快照（每日每物料每仓库一行），是库存数量/金额的唯一权威来源，
-- 不能再用出入库流水推导（流水只有进出量，没有结存）。
-- ------------------------------------------------------------
SET @ods_max = (SELECT MAX(snapshot_date) FROM ods_db.ods_wms_stock_snapshot);
SET @dwd_max = (SELECT MAX(snapshot_date) FROM dwd_db.dwd_stock_snapshot);
SET @p1 = CONCAT('p', DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y%m'));
SET @p2 = CONCAT('p', DATE_FORMAT(@ods_max, '%Y%m'));
SET @sql = IF(@dwd_max IS NULL,
    'TRUNCATE TABLE dwd_db.dwd_stock_snapshot',
    CONCAT('ALTER TABLE dwd_db.dwd_stock_snapshot TRUNCATE PARTITION ', @p1, ',', @p2));
PREPARE st FROM @sql;
EXECUTE st;
DEALLOCATE PREPARE st;
SET @d1 = IF(@dwd_max IS NULL,
    (SELECT MIN(snapshot_date) FROM ods_db.ods_wms_stock_snapshot),
    DATE_FORMAT(DATE_SUB(@ods_max, INTERVAL 1 MONTH), '%Y-%m-01'));
INSERT INTO dwd_db.dwd_stock_snapshot ( snapshot_date, material_id, warehouse_id, stock_qty, stock_amount ) SELECT
snapshot_date,
material_id,
warehouse_id,
SUM( stock_qty ) AS stock_qty,
SUM( stock_amount ) AS stock_amount
FROM
	ods_db.ods_wms_stock_snapshot
WHERE
	snapshot_date BETWEEN @d1 AND @ods_max
	AND snapshot_id IS NOT NULL
	AND material_id IS NOT NULL
	AND snapshot_date IS NOT NULL
GROUP BY
	snapshot_date,
	material_id,
	warehouse_id;
