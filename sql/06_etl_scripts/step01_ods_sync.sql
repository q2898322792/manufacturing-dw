-- ============================================================
-- step01_ods_sync.sql（增量同步 · 幂等版）
-- ============================================================
-- 设计思路：水位表(watermark) + 增量过滤 + 按主键 UPSERT
--
--  1. 首次执行：水位不存在/为空 -> 初始化为 1970-01-01 -> 全量同步；
--  2. 后续执行：只处理 update_time > 上次水位的“新增/修改”数据；
--  3. 源表主键冲突时改为“更新”(ON DUPLICATE KEY UPDATE)：
--     - 同一张表、同一批数据重复执行不会报 1062 主键冲突；
--     - 中途失败后重跑也能收敛，不会越跑越错；
--  4. 全部表同步成功后才推进水位（last_sync），失败则回滚、水位不动，
--     下次重跑会从断点继续，不丢数据。
--
--  边界说明：
--  - ODS 保存的是“源表最新状态镜像”（每行追加 etl_time 同步时间戳）；
--  - 源库“物理删除”的行不会自动传播到 ODS（如需支持可另加删除日志表/软删除）；
--  - 要求：源表必须有 update_time 列，且 ODS 表结构与源表一致、仅多出 etl_time 列。
-- ============================================================

-- ------------------------------------------------------------
-- 1. 水位表：不存在则创建（幂等，可重复执行）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ods_db.etl_watermark (
    table_name  VARCHAR(100) PRIMARY KEY COMMENT 'ODS 表名',
    last_sync   DATETIME COMMENT '上次同步水位（含）',
    update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '水位记录更新时间'
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS 增量同步水位表';

-- ------------------------------------------------------------
-- 2. 初始化水位：只“补缺”，绝不覆盖已有水位！
--    ⚠️ 注意：这里不能用 ON DUPLICATE KEY UPDATE last_sync='1970-01-01'，
--    否则每次执行都会把水位重置回 1970，导致第二次运行做全量重灌 -> 主键冲突。
-- ------------------------------------------------------------
INSERT IGNORE INTO ods_db.etl_watermark (table_name, last_sync)
VALUES
    ('ods_erp_customer',            '1970-01-01 00:00:00'),
    ('ods_erp_product',             '1970-01-01 00:00:00'),
    ('ods_erp_material',            '1970-01-01 00:00:00'),
    ('ods_erp_sale_order',          '1970-01-01 00:00:00'),
    ('ods_erp_cost_voucher',        '1970-01-01 00:00:00'),
    ('ods_mes_workshop',            '1970-01-01 00:00:00'),
    ('ods_mes_workorder',           '1970-01-01 00:00:00'),
    ('ods_mes_equipment_runtime',   '1970-01-01 00:00:00'),
    ('ods_wms_supplier',            '1970-01-01 00:00:00'),
    ('ods_wms_stock_io',            '1970-01-01 00:00:00'),
    ('ods_wms_stock_snapshot',      '1970-01-01 00:00:00');

-- ------------------------------------------------------------
-- 3. 记录本次同步时间（同一连接内全程有效，供增量过滤与水位推进使用）
-- ------------------------------------------------------------
SET @sync_time = NOW();

-- ------------------------------------------------------------
-- 4. 增量同步（每张表：水位过滤 + UPSERT）
--    规则：只取 update_time 大于上次水位的行；
--    命中主键冲突(源表已存在且本轮有更新)则整行刷新为源表最新值。
-- ------------------------------------------------------------

-- 4.1 ERP 客户
INSERT INTO ods_db.ods_erp_customer
    (customer_id, customer_name, region, grade, type, industry,
     contact_person, contact_phone, create_time, update_time, etl_time)
SELECT customer_id, customer_name, region, grade, type, industry,
       contact_person, contact_phone, create_time, update_time, @sync_time
FROM erp_db.customer
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_erp_customer')
ON DUPLICATE KEY UPDATE
    customer_name  = VALUES(customer_name),
    region         = VALUES(region),
    grade          = VALUES(grade),
    type           = VALUES(type),
    industry       = VALUES(industry),
    contact_person = VALUES(contact_person),
    contact_phone  = VALUES(contact_phone),
    create_time    = VALUES(create_time),
    update_time    = VALUES(update_time),
    etl_time       = @sync_time;

-- 4.2 ERP 产品
INSERT INTO ods_db.ods_erp_product
    (product_id, product_name, category_l1, category_l2, category_l3,
     spec, unit, standard_cost, create_time, update_time, etl_time)
SELECT product_id, product_name, category_l1, category_l2, category_l3,
       spec, unit, standard_cost, create_time, update_time, @sync_time
FROM erp_db.product
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_erp_product')
ON DUPLICATE KEY UPDATE
    product_name  = VALUES(product_name),
    category_l1   = VALUES(category_l1),
    category_l2   = VALUES(category_l2),
    category_l3   = VALUES(category_l3),
    spec          = VALUES(spec),
    unit          = VALUES(unit),
    standard_cost = VALUES(standard_cost),
    create_time   = VALUES(create_time),
    update_time   = VALUES(update_time),
    etl_time      = @sync_time;

-- 4.3 ERP 物料
INSERT INTO ods_db.ods_erp_material
    (material_id, material_name, category, sub_category, spec, unit,
     safety_stock, standard_cost, source_system, create_time, update_time, etl_time)
SELECT material_id, material_name, category, sub_category, spec, unit,
       safety_stock, standard_cost, source_system, create_time, update_time, @sync_time
FROM erp_db.material
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_erp_material')
ON DUPLICATE KEY UPDATE
    material_name  = VALUES(material_name),
    category       = VALUES(category),
    sub_category   = VALUES(sub_category),
    spec           = VALUES(spec),
    unit           = VALUES(unit),
    safety_stock   = VALUES(safety_stock),
    standard_cost  = VALUES(standard_cost),
    source_system  = VALUES(source_system),
    create_time    = VALUES(create_time),
    update_time    = VALUES(update_time),
    etl_time       = @sync_time;

-- 4.4 ERP 销售订单
INSERT INTO ods_db.ods_erp_sale_order
    (order_id, customer_id, product_id, order_date, order_amount, tax_amount,
     discount_amount, net_amount, order_status, delivery_date, payment_date,
     region, quantity, create_time, update_time, etl_time)
SELECT order_id, customer_id, product_id, order_date, order_amount, tax_amount,
       discount_amount, net_amount, order_status, delivery_date, payment_date,
       region, quantity, create_time, update_time, @sync_time
FROM erp_db.sale_order
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_erp_sale_order')
ON DUPLICATE KEY UPDATE
    customer_id     = VALUES(customer_id),
    product_id      = VALUES(product_id),
    order_date      = VALUES(order_date),
    order_amount    = VALUES(order_amount),
    tax_amount      = VALUES(tax_amount),
    discount_amount = VALUES(discount_amount),
    net_amount      = VALUES(net_amount),
    order_status    = VALUES(order_status),
    delivery_date   = VALUES(delivery_date),
    payment_date    = VALUES(payment_date),
    region          = VALUES(region),
    quantity        = VALUES(quantity),
    create_time     = VALUES(create_time),
    update_time     = VALUES(update_time),
    etl_time        = @sync_time;

-- 4.5 ERP 成本凭证
INSERT INTO ods_db.ods_erp_cost_voucher
    (voucher_id, product_id, workshop_id, workorder_id, material_cost,
     labor_cost, mfg_cost, total_cost, cost_month, create_time, update_time, etl_time)
SELECT voucher_id, product_id, workshop_id, workorder_id, material_cost,
       labor_cost, mfg_cost, total_cost, cost_month, create_time, update_time, @sync_time
FROM erp_db.cost_voucher
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_erp_cost_voucher')
ON DUPLICATE KEY UPDATE
    product_id    = VALUES(product_id),
    workshop_id   = VALUES(workshop_id),
    workorder_id  = VALUES(workorder_id),
    material_cost = VALUES(material_cost),
    labor_cost    = VALUES(labor_cost),
    mfg_cost      = VALUES(mfg_cost),
    total_cost    = VALUES(total_cost),
    cost_month    = VALUES(cost_month),
    create_time   = VALUES(create_time),
    update_time   = VALUES(update_time),
    etl_time      = @sync_time;

-- 4.6 MES 车间
INSERT INTO ods_db.ods_mes_workshop
    (workshop_id, workshop_name, production_line, workshop_type,
     capacity_per_day, create_time, update_time, etl_time)
SELECT workshop_id, workshop_name, production_line, workshop_type,
       capacity_per_day, create_time, update_time, @sync_time
FROM mes_db.workshop
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_mes_workshop')
ON DUPLICATE KEY UPDATE
    workshop_name    = VALUES(workshop_name),
    production_line  = VALUES(production_line),
    workshop_type    = VALUES(workshop_type),
    capacity_per_day = VALUES(capacity_per_day),
    create_time      = VALUES(create_time),
    update_time      = VALUES(update_time),
    etl_time         = @sync_time;

-- 4.7 MES 生产工单
INSERT INTO ods_db.ods_mes_workorder
    (workorder_id, product_id, workshop_id, plan_qty, actual_qty, qualified_qty,
     defect_qty, defect_type, plan_start_date, plan_end_date, actual_start_date,
     actual_end_date, workorder_status, labor_hours, material_loss,
     create_time, update_time, etl_time)
SELECT workorder_id, product_id, workshop_id, plan_qty, actual_qty, qualified_qty,
       defect_qty, defect_type, plan_start_date, plan_end_date, actual_start_date,
       actual_end_date, workorder_status, labor_hours, material_loss,
       create_time, update_time, @sync_time
FROM mes_db.produce_workorder
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_mes_workorder')
ON DUPLICATE KEY UPDATE
    product_id       = VALUES(product_id),
    workshop_id      = VALUES(workshop_id),
    plan_qty         = VALUES(plan_qty),
    actual_qty       = VALUES(actual_qty),
    qualified_qty    = VALUES(qualified_qty),
    defect_qty       = VALUES(defect_qty),
    defect_type      = VALUES(defect_type),
    plan_start_date  = VALUES(plan_start_date),
    plan_end_date    = VALUES(plan_end_date),
    actual_start_date = VALUES(actual_start_date),
    actual_end_date  = VALUES(actual_end_date),
    workorder_status = VALUES(workorder_status),
    labor_hours      = VALUES(labor_hours),
    material_loss    = VALUES(material_loss),
    create_time      = VALUES(create_time),
    update_time      = VALUES(update_time),
    etl_time         = @sync_time;

-- 4.8 MES 设备运行记录
INSERT INTO ods_db.ods_mes_equipment_runtime
    (record_id, equipment_id, workshop_id, record_date, runtime_min, idle_min,
     fault_min, maintain_min, total_min, create_time, update_time, etl_time)
SELECT record_id, equipment_id, workshop_id, record_date, runtime_min, idle_min,
       fault_min, maintain_min, total_min, create_time, update_time, @sync_time
FROM mes_db.equipment_runtime
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_mes_equipment_runtime')
ON DUPLICATE KEY UPDATE
    equipment_id = VALUES(equipment_id),
    workshop_id  = VALUES(workshop_id),
    record_date  = VALUES(record_date),
    runtime_min  = VALUES(runtime_min),
    idle_min     = VALUES(idle_min),
    fault_min    = VALUES(fault_min),
    maintain_min = VALUES(maintain_min),
    total_min    = VALUES(total_min),
    create_time  = VALUES(create_time),
    update_time  = VALUES(update_time),
    etl_time     = @sync_time;

-- 4.9 WMS 供应商
INSERT INTO ods_db.ods_wms_supplier
    (supplier_id, supplier_name, supply_category, cooperation_grade,
     cooperation_status, contact_person, contact_phone, create_time, update_time, etl_time)
SELECT supplier_id, supplier_name, supply_category, cooperation_grade,
       cooperation_status, contact_person, contact_phone, create_time, update_time, @sync_time
FROM wms_db.supplier
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_wms_supplier')
ON DUPLICATE KEY UPDATE
    supplier_name     = VALUES(supplier_name),
    supply_category   = VALUES(supply_category),
    cooperation_grade = VALUES(cooperation_grade),
    cooperation_status = VALUES(cooperation_status),
    contact_person    = VALUES(contact_person),
    contact_phone     = VALUES(contact_phone),
    create_time       = VALUES(create_time),
    update_time       = VALUES(update_time),
    etl_time          = @sync_time;

-- 4.10 WMS 出入库明细
INSERT INTO ods_db.ods_wms_stock_io
    (io_id, material_id, warehouse_id, io_type, io_qty, io_amount, unit_price,
     io_date, supplier_id, workorder_id, order_id, create_time, update_time, etl_time)
SELECT io_id, material_id, warehouse_id, io_type, io_qty, io_amount, unit_price,
       io_date, supplier_id, workorder_id, order_id, create_time, update_time, @sync_time
FROM wms_db.stock_io_detail
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_wms_stock_io')
ON DUPLICATE KEY UPDATE
    material_id  = VALUES(material_id),
    warehouse_id = VALUES(warehouse_id),
    io_type      = VALUES(io_type),
    io_qty       = VALUES(io_qty),
    io_amount    = VALUES(io_amount),
    unit_price   = VALUES(unit_price),
    io_date      = VALUES(io_date),
    supplier_id  = VALUES(supplier_id),
    workorder_id = VALUES(workorder_id),
    order_id     = VALUES(order_id),
    create_time  = VALUES(create_time),
    update_time  = VALUES(update_time),
    etl_time     = @sync_time;

-- 4.11 WMS 库存快照
INSERT INTO ods_db.ods_wms_stock_snapshot
    (snapshot_id, material_id, warehouse_id, snapshot_date, stock_qty,
     stock_amount, create_time, update_time, etl_time)
SELECT snapshot_id, material_id, warehouse_id, snapshot_date, stock_qty,
       stock_amount, create_time, update_time, @sync_time
FROM wms_db.stock_snapshot
WHERE update_time > (SELECT last_sync FROM ods_db.etl_watermark WHERE table_name = 'ods_wms_stock_snapshot')
ON DUPLICATE KEY UPDATE
    material_id   = VALUES(material_id),
    warehouse_id  = VALUES(warehouse_id),
    snapshot_date = VALUES(snapshot_date),
    stock_qty     = VALUES(stock_qty),
    stock_amount  = VALUES(stock_amount),
    create_time   = VALUES(create_time),
    update_time   = VALUES(update_time),
    etl_time      = @sync_time;

-- ------------------------------------------------------------
-- 5. 全部表同步成功后，推进水位（记录本次同步时间）
--    ⚠️ 该语句与本文件所有 INSERT 在同一事务中：任一步失败回滚，水位不动。
-- ------------------------------------------------------------
UPDATE ods_db.etl_watermark
SET last_sync = @sync_time
WHERE table_name IN ('ods_erp_customer', 'ods_erp_product', 'ods_erp_material',
                     'ods_erp_sale_order', 'ods_erp_cost_voucher',
                     'ods_mes_workshop', 'ods_mes_workorder', 'ods_mes_equipment_runtime',
                     'ods_wms_supplier', 'ods_wms_stock_io', 'ods_wms_stock_snapshot');
