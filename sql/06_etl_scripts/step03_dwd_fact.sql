-- 先清空事实表（全量重建；表名带库前缀，不依赖 USE 选择默认库）
TRUNCATE TABLE dwd_db.dwd_sale_order_detail;
TRUNCATE TABLE dwd_db.dwd_produce_workorder_detail;
TRUNCATE TABLE dwd_db.dwd_stock_io_detail;
TRUNCATE TABLE dwd_db.dwd_cost_detail;
TRUNCATE TABLE dwd_db.dwd_equipment_runtime;
TRUNCATE TABLE dwd_db.dwd_stock_snapshot;
-- 6. 销售订单事实表
-- 过滤条件：订单号不为空、状态不是已作废、金额大于0小于1000万
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
	order_id IS NOT NULL 
	AND order_status != '已作废' 
	AND order_amount > 0 
	AND order_amount < 10000000;
-- 7. 生产工单事实表
-- 过滤条件：工单号不为空、实际产量不超过计划产量的2倍
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
	workorder_id IS NOT NULL 
	AND actual_qty <= plan_qty * 2;
-- 8. 出入库明细事实表
-- 过滤条件：记录ID不为空、数量大于0
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
	io_id IS NOT NULL 
	AND io_qty > 0;
-- 9. 成本明细事实表
-- 过滤条件：凭证ID不为空、总成本大于0
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
	voucher_id IS NOT NULL 
	AND total_cost > 0;
-- 10. 设备运行记录事实表
-- 过滤条件：记录ID不为空、运行时间大于0
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
	record_id IS NOT NULL 
	AND runtime_min > 0;
-- 11. 库存快照事实表
-- 来源 WMS 库存快照（每日每物料每仓库一行），是库存数量/金额的唯一权威来源，
-- 不能再用出入库流水推导（流水只有进出量，没有结存）。
INSERT INTO dwd_db.dwd_stock_snapshot ( snapshot_date, material_id, warehouse_id, stock_qty, stock_amount ) SELECT
snapshot_date,
material_id,
warehouse_id,
SUM( stock_qty ) AS stock_qty,
SUM( stock_amount ) AS stock_amount 
FROM
	ods_db.ods_wms_stock_snapshot 
WHERE
	snapshot_id IS NOT NULL 
	AND material_id IS NOT NULL 
	AND snapshot_date IS NOT NULL 
GROUP BY
	snapshot_date,
	material_id,
	warehouse_id;