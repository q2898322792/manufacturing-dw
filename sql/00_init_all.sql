-- ============================================================
-- 00_init_all.sql —— 一次性初始化：建 7 个库 + 全部分层表
-- 用法：mysql -uroot -p < 00_init_all.sql
-- 幂等：CREATE DATABASE IF NOT EXISTS / DROP TABLE IF EXISTS 均可重复执行
-- 说明：dim_date 只建空表，数据由 step02 按实际日期动态重建
--
-- ⚠️ 本文件由 scripts/build_init_sql.py 自动生成，请勿手改；
--    改了 sql/01~05 里的建表脚本后，跑一下该脚本重新生成。
-- ============================================================

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS erp_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS mes_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS wms_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS ods_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS dwd_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS dws_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS ads_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- ============================================================
-- erp_db（5 张表）
-- ============================================================
USE erp_db;

-- ---------- cost_voucher.sql ----------
DROP TABLE IF EXISTS cost_voucher;
CREATE TABLE cost_voucher (
	voucher_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '凭证ID（主键）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联product表）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联workshop表）',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID（关联produce_workorder表）',
	material_cost DECIMAL ( 12, 2 ) COMMENT '物料成本（元）',
	labor_cost DECIMAL ( 12, 2 ) COMMENT '人工成本（元）',
	mfg_cost DECIMAL ( 12, 2 ) COMMENT '制造费用（元）',
	total_cost DECIMAL ( 12, 2 ) COMMENT '总成本（元）',
	cost_month VARCHAR ( 7 ) COMMENT '成本月份（YYYY-MM）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_workorder_id ( workorder_id ),
	INDEX idx_product_id ( product_id ),
INDEX idx_cost_month ( cost_month ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '成本凭证事实表';

-- ---------- customer.sql ----------
DROP TABLE IF EXISTS customer;
CREATE TABLE customer (
    customer_id VARCHAR(32) PRIMARY KEY COMMENT '客户ID（主键）',
    customer_name VARCHAR(100) NOT NULL COMMENT '客户名称',
    region VARCHAR(50) COMMENT '所属区域（华东/华南/华北/西南/西北/华中/东北）',
    grade VARCHAR(20) COMMENT '客户等级（A/B/C/D）',
    type VARCHAR(20) COMMENT '客户类型（企业/个人/政府）',
    industry VARCHAR(50) COMMENT '所属行业',
    contact_person VARCHAR(50) COMMENT '联系人',
    contact_phone VARCHAR(20) COMMENT '联系电话',
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='客户维度表';

-- ---------- material.sql ----------
DROP TABLE IF EXISTS material;
CREATE TABLE material (
	material_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '物料ID（主键）',
	material_name VARCHAR ( 100 ) NOT NULL COMMENT '物料名称',
	category VARCHAR ( 50 ) COMMENT '物料大类（原材料/辅料/半成品/成品）',
	sub_category VARCHAR ( 50 ) COMMENT '物料子类（电子件/结构件/塑胶件/包材/五金）',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位（个/套/米/公斤）',
	safety_stock INT DEFAULT 0 COMMENT '安全库存',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	source_system VARCHAR ( 20 ) DEFAULT 'erp' COMMENT '来源系统',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '物料维度表';

-- ---------- product.sql ----------
DROP TABLE IF EXISTS product;
CREATE TABLE product (
	product_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '产品ID（主键）',
	product_name VARCHAR ( 100 ) NOT NULL COMMENT '产品名称',
	category_l1 VARCHAR ( 50 ) COMMENT '一级品类',
	category_l2 VARCHAR ( 50 ) COMMENT '二级品类',
	category_l3 VARCHAR ( 50 ) COMMENT '三级品类',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位（台/套/个/米）',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '产品维度表';

-- ---------- sale_order.sql ----------
DROP TABLE IF EXISTS sale_order;
CREATE TABLE sale_order (
	order_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '订单号（主键）',
	customer_id VARCHAR ( 32 ) COMMENT '客户ID（关联customer表）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联product表）',
	order_date DATE COMMENT '下单日期',
	order_amount DECIMAL ( 12, 2 ) COMMENT '订单含税总金额（元）',
	tax_amount DECIMAL ( 12, 2 ) COMMENT '税额（元）',
	discount_amount DECIMAL ( 12, 2 ) DEFAULT 0 COMMENT '优惠金额（元）',
	net_amount DECIMAL ( 12, 2 ) COMMENT '实付金额（元）',
	order_status VARCHAR ( 20 ) COMMENT '订单状态（已提交/已发货/已完成/已取消/已作废）',
	delivery_date DATE COMMENT '实际发货日期',
	payment_date DATE COMMENT '回款日期',
	region VARCHAR ( 50 ) COMMENT '客户区域（冗余字段，便于区域分析）',
	quantity INT COMMENT '订购数量',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_order_date ( order_date ),
	INDEX idx_customer_id ( customer_id ),
	INDEX idx_product_id ( product_id ),
INDEX idx_order_status ( order_status ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '销售订单事实表';

-- ============================================================
-- mes_db（3 张表）
-- ============================================================
USE mes_db;

-- ---------- equipment_runtime.sql ----------
DROP TABLE IF EXISTS equipment_runtime;
CREATE TABLE equipment_runtime (
	record_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '记录ID（主键）',
	equipment_id VARCHAR ( 32 ) COMMENT '设备ID',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联workshop表）',
	record_date DATE COMMENT '记录日期',
	runtime_min INT COMMENT '实际运行分钟数',
	idle_min INT COMMENT '空闲分钟数',
	fault_min INT COMMENT '故障停机分钟数',
	maintain_min INT COMMENT '计划维护分钟数',
	total_min INT DEFAULT 1440 COMMENT '当日总分钟数（通常为1440）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_record_date ( record_date ),
	INDEX idx_equipment_id ( equipment_id ),
INDEX idx_workshop_id ( workshop_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '设备运行记录事实表';

-- ---------- produce_workorder.sql ----------
DROP TABLE IF EXISTS produce_workorder;
CREATE TABLE produce_workorder (
	workorder_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '工单号（主键）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联product表）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联workshop表）',
	plan_qty INT COMMENT '计划产量',
	actual_qty INT COMMENT '实际产量（合格品入库数量）',
	qualified_qty INT COMMENT '良品数量',
	defect_qty INT COMMENT '不良品数量',
	defect_type VARCHAR ( 50 ) COMMENT '主要不良类型（尺寸偏差/外观缺陷/性能失效/其他）',
	plan_start_date DATE COMMENT '计划开工日期',
	plan_end_date DATE COMMENT '计划完工日期',
	actual_start_date DATE COMMENT '实际开工日期',
	actual_end_date DATE COMMENT '实际完工日期',
	workorder_status VARCHAR ( 20 ) COMMENT '工单状态（未开工/生产中/已完工/已关闭/已逾期）',
	labor_hours DECIMAL ( 10, 2 ) COMMENT '人工工时（小时）',
	material_loss DECIMAL ( 12, 2 ) COMMENT '物料损耗金额（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_plan_start_date ( plan_start_date ),
	INDEX idx_product_id ( product_id ),
	INDEX idx_workshop_id ( workshop_id ),
INDEX idx_workorder_status ( workorder_status ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '生产工单事实表';

-- ---------- workshop.sql ----------
DROP TABLE IF EXISTS workshop;
CREATE TABLE workshop (
	workshop_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '车间ID（主键）',
	workshop_name VARCHAR ( 50 ) NOT NULL COMMENT '车间名称',
	production_line VARCHAR ( 50 ) COMMENT '所属产线（一车间/二车间/三车间）',
	workshop_type VARCHAR ( 20 ) COMMENT '车间类型（冲压/焊接/装配/涂装/加工）',
	capacity_per_day INT DEFAULT 0 COMMENT '日设计产能（件）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '车间维度表';

-- ============================================================
-- wms_db（3 张表）
-- ============================================================
USE wms_db;

-- ---------- stock_io_detail.sql ----------
DROP TABLE IF EXISTS stock_io_detail;
CREATE TABLE stock_io_detail (
	io_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '出入库记录ID（主键）',
	material_id VARCHAR ( 32 ) COMMENT '物料ID（关联material表）',
	warehouse_id VARCHAR ( 32 ) COMMENT '仓库ID（原材料仓/半成品仓/成品仓）',
	io_type VARCHAR ( 10 ) COMMENT '出入库类型（IN/OUT）',
	io_qty INT COMMENT '数量',
	io_amount DECIMAL ( 12, 2 ) COMMENT '总金额（元）',
	unit_price DECIMAL ( 12, 2 ) COMMENT '单价（元）',
	io_date DATE COMMENT '出入库日期',
	supplier_id VARCHAR ( 32 ) COMMENT '供应商ID（采购入库时关联supplier表）',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID（生产领料时关联produce_workorder表）',
	order_id VARCHAR ( 32 ) COMMENT '订单ID（销售出库时关联sale_order表）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_io_date ( io_date ),
	INDEX idx_material_id ( material_id ),
	INDEX idx_io_type ( io_type ),
	INDEX idx_workorder_id ( workorder_id ),
INDEX idx_order_id ( order_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '出入库明细事实表';

-- ---------- stock_snapshot.sql ----------
DROP TABLE IF EXISTS stock_snapshot;
CREATE TABLE stock_snapshot (
	snapshot_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '快照ID（主键）',
	material_id VARCHAR ( 32 ) COMMENT '物料ID（关联material表）',
	warehouse_id VARCHAR ( 32 ) COMMENT '仓库ID',
	snapshot_date DATE COMMENT '快照日期',
	stock_qty INT COMMENT '库存数量',
	stock_amount DECIMAL ( 12, 2 ) COMMENT '库存金额（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_snapshot_date ( snapshot_date ),
	INDEX idx_material_id ( material_id ),
UNIQUE KEY uk_material_warehouse_date ( material_id, warehouse_id, snapshot_date ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '库存每日快照事实表';

-- ---------- supplier.sql ----------
DROP TABLE IF EXISTS supplier;
CREATE TABLE supplier (
	supplier_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '供应商ID（主键）',
	supplier_name VARCHAR ( 100 ) NOT NULL COMMENT '供应商名称',
	supply_category VARCHAR ( 50 ) COMMENT '供应品类',
	cooperation_grade VARCHAR ( 20 ) COMMENT '合作等级（A/B/C/D）',
	cooperation_status VARCHAR ( 20 ) COMMENT '合作状态（合作中/已终止）',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '供应商维度表';

-- ============================================================
-- ods_db（11 张表）
-- ============================================================
USE ods_db;

-- ---------- ods_erp_cost_voucher.sql ----------
DROP TABLE IF EXISTS ods_erp_cost_voucher;
CREATE TABLE ods_erp_cost_voucher (
	voucher_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '凭证ID（主键）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID',
	material_cost DECIMAL ( 12, 2 ) COMMENT '物料成本（元）',
	labor_cost DECIMAL ( 12, 2 ) COMMENT '人工成本（元）',
	mfg_cost DECIMAL ( 12, 2 ) COMMENT '制造费用（元）',
	total_cost DECIMAL ( 12, 2 ) COMMENT '总成本（元）',
	cost_month VARCHAR ( 7 ) COMMENT '成本月份（YYYY-MM）',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间',
INDEX idx_cost_month ( cost_month )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-成本凭证事实表';

-- ---------- ods_erp_customer.sql ----------
DROP TABLE IF EXISTS ods_erp_customer;
CREATE TABLE ods_erp_customer (
	customer_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '客户ID（主键）',
	customer_name VARCHAR ( 100 ) NOT NULL COMMENT '客户名称',
	region VARCHAR ( 50 ) COMMENT '所属区域',
	grade VARCHAR ( 20 ) COMMENT '客户等级',
	type VARCHAR ( 20 ) COMMENT '客户类型',
	industry VARCHAR ( 50 ) COMMENT '所属行业',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-客户维度表';

-- ---------- ods_erp_material.sql ----------
DROP TABLE IF EXISTS ods_erp_material;
CREATE TABLE ods_erp_material (
	material_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '物料ID（主键）',
	material_name VARCHAR ( 100 ) NOT NULL COMMENT '物料名称',
	category VARCHAR ( 50 ) COMMENT '物料大类（原材料/辅料/半成品/成品）',
	sub_category VARCHAR ( 50 ) COMMENT '物料子类（电子件/结构件/塑胶件/包材/五金）',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位（个/套/米/公斤）',
	safety_stock INT DEFAULT 0 COMMENT '安全库存',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	source_system VARCHAR ( 20 ) DEFAULT 'erp' COMMENT '来源系统',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-物料维度表';

-- ---------- ods_erp_product.sql ----------
DROP TABLE IF EXISTS ods_erp_product;
CREATE TABLE ods_erp_product (
	product_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '产品ID（主键）',
	product_name VARCHAR ( 100 ) NOT NULL COMMENT '产品名称',
	category_l1 VARCHAR ( 50 ) COMMENT '一级品类',
	category_l2 VARCHAR ( 50 ) COMMENT '二级品类',
	category_l3 VARCHAR ( 50 ) COMMENT '三级品类',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-产品维度表';

-- ---------- ods_erp_sale_order.sql ----------
DROP TABLE IF EXISTS ods_erp_sale_order;
CREATE TABLE ods_erp_sale_order (
	order_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '订单号（主键）',
	customer_id VARCHAR ( 32 ) COMMENT '客户ID',
	product_id VARCHAR ( 32 ) COMMENT '产品ID',
	order_date DATE COMMENT '下单日期',
	order_amount DECIMAL ( 12, 2 ) COMMENT '订单含税总金额（元）',
	tax_amount DECIMAL ( 12, 2 ) COMMENT '税额（元）',
	discount_amount DECIMAL ( 12, 2 ) DEFAULT 0 COMMENT '优惠金额（元）',
	net_amount DECIMAL ( 12, 2 ) COMMENT '实付金额（元）',
	order_status VARCHAR ( 20 ) COMMENT '订单状态（已提交/已发货/已完成/已取消/已作废）',
	delivery_date DATE COMMENT '实际发货日期',
	payment_date DATE COMMENT '回款日期',
	region VARCHAR ( 50 ) COMMENT '客户区域',
	quantity INT COMMENT '订购数量',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间',
INDEX idx_order_date ( order_date )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-销售订单事实表';

-- ---------- ods_mes_equipment_runtime.sql ----------
DROP TABLE IF EXISTS ods_mes_equipment_runtime;
CREATE TABLE ods_mes_equipment_runtime (
	record_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '记录ID（主键）',
	equipment_id VARCHAR ( 32 ) COMMENT '设备ID',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID',
	record_date DATE COMMENT '记录日期',
	runtime_min INT COMMENT '实际运行分钟数',
	idle_min INT COMMENT '空闲分钟数',
	fault_min INT COMMENT '故障停机分钟数',
	maintain_min INT COMMENT '计划维护分钟数',
	total_min INT DEFAULT 1440 COMMENT '当日总分钟数',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间',
INDEX idx_record_date ( record_date )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-设备运行记录事实表';

-- ---------- ods_mes_workorder.sql ----------
DROP TABLE IF EXISTS ods_mes_workorder;
CREATE TABLE ods_mes_workorder (
	workorder_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '工单号（主键）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID',
	plan_qty INT COMMENT '计划产量',
	actual_qty INT COMMENT '实际产量',
	qualified_qty INT COMMENT '良品数量',
	defect_qty INT COMMENT '不良品数量',
	defect_type VARCHAR ( 50 ) COMMENT '主要不良类型',
	plan_start_date DATE COMMENT '计划开工日期',
	plan_end_date DATE COMMENT '计划完工日期',
	actual_start_date DATE COMMENT '实际开工日期',
	actual_end_date DATE COMMENT '实际完工日期',
	workorder_status VARCHAR ( 20 ) COMMENT '工单状态',
	labor_hours DECIMAL ( 10, 2 ) COMMENT '人工工时（小时）',
	material_loss DECIMAL ( 12, 2 ) COMMENT '物料损耗金额（元）',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间',
INDEX idx_plan_start_date ( plan_start_date )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-生产工单事实表';

-- ---------- ods_mes_workshop.sql ----------
DROP TABLE IF EXISTS ods_mes_workshop;
CREATE TABLE ods_mes_workshop (
	workshop_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '车间ID（主键）',
	workshop_name VARCHAR ( 50 ) NOT NULL COMMENT '车间名称',
	production_line VARCHAR ( 50 ) COMMENT '所属产线',
	workshop_type VARCHAR ( 20 ) COMMENT '车间类型',
	capacity_per_day INT DEFAULT 0 COMMENT '日设计产能（件）',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-车间维度表';

-- ---------- ods_wms_stock_io.sql ----------
DROP TABLE IF EXISTS ods_wms_stock_io;
CREATE TABLE ods_wms_stock_io (
	io_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '出入库记录ID（主键）',
	material_id VARCHAR ( 32 ) COMMENT '物料ID',
	warehouse_id VARCHAR ( 32 ) COMMENT '仓库ID',
	io_type VARCHAR ( 10 ) COMMENT '出入库类型（IN/OUT）',
	io_qty INT COMMENT '数量',
	io_amount DECIMAL ( 12, 2 ) COMMENT '总金额（元）',
	unit_price DECIMAL ( 12, 2 ) COMMENT '单价（元）',
	io_date DATE COMMENT '出入库日期',
	supplier_id VARCHAR ( 32 ) COMMENT '供应商ID',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID',
	order_id VARCHAR ( 32 ) COMMENT '订单ID',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间',
INDEX idx_io_date ( io_date )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-出入库明细事实表';

-- ---------- ods_wms_stock_snapshot.sql ----------
DROP TABLE IF EXISTS ods_wms_stock_snapshot;
CREATE TABLE ods_wms_stock_snapshot (
	snapshot_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '快照ID（主键）',
	material_id VARCHAR ( 32 ) COMMENT '物料ID',
	warehouse_id VARCHAR ( 32 ) COMMENT '仓库ID',
	snapshot_date DATE COMMENT '快照日期',
	stock_qty INT COMMENT '库存数量',
	stock_amount DECIMAL ( 12, 2 ) COMMENT '库存金额（元）',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间',
INDEX idx_snapshot_date ( snapshot_date )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-库存快照事实表';

-- ---------- ods_wms_supplier.sql ----------
DROP TABLE IF EXISTS ods_wms_supplier;
CREATE TABLE ods_wms_supplier (
	supplier_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '供应商ID（主键）',
	supplier_name VARCHAR ( 100 ) NOT NULL COMMENT '供应商名称',
	supply_category VARCHAR ( 50 ) COMMENT '供应品类',
	cooperation_grade VARCHAR ( 20 ) COMMENT '合作等级（A/B/C/D）',
	cooperation_status VARCHAR ( 20 ) COMMENT '合作状态（合作中/已终止）',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-供应商维度表';

-- ============================================================
-- dwd_db（13 张表）
-- ============================================================
USE dwd_db;

-- ---------- dim_customer.sql ----------
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
	customer_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '客户ID（主键，与源系统一致）',
	customer_name VARCHAR ( 100 ) NOT NULL COMMENT '客户名称',
	region VARCHAR ( 50 ) COMMENT '所属区域',
	grade VARCHAR ( 20 ) COMMENT '客户等级（A/B/C/D）',
	type VARCHAR ( 20 ) COMMENT '客户类型（企业/个人/政府）',
	industry VARCHAR ( 50 ) COMMENT '所属行业',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-客户维度表';

-- ---------- dim_date.sql ----------
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date (
	date_key DATE PRIMARY KEY COMMENT '日期（主键）',
	YEAR INT COMMENT '年',
	QUARTER INT COMMENT '季度（1-4）',
	MONTH INT COMMENT '月份（1-12）',
	WEEK INT COMMENT '周数',
	DAY INT COMMENT '日（1-31）',
	is_workday TINYINT COMMENT '是否工作日（1=是，0=否）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-日期维度表';

-- 说明：本表数据不再在此写死日期初始化；
--       由 step02_dwd_dimension.sql 按 ODS 各事实表的实际日期范围动态重建（TRUNCATE + 递归插入）。

-- ---------- dim_equipment.sql ----------
DROP TABLE IF EXISTS dim_equipment;
CREATE TABLE dim_equipment (
	equipment_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '设备ID（主键）',
	equipment_name VARCHAR ( 100 ) COMMENT '设备名称',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	equipment_type VARCHAR ( 50 ) COMMENT '设备类型',
	purchase_date DATE COMMENT '采购日期',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-设备维度表';

-- ---------- dim_material.sql ----------
DROP TABLE IF EXISTS dim_material;
CREATE TABLE dim_material (
	material_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '物料ID（主键，与源系统一致）',
	material_name VARCHAR ( 100 ) NOT NULL COMMENT '物料名称',
	category VARCHAR ( 50 ) COMMENT '物料大类（原材料/辅料/半成品/成品）',
	sub_category VARCHAR ( 50 ) COMMENT '物料子类（电子件/结构件/塑胶件/包材/五金）',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位',
	safety_stock INT DEFAULT 0 COMMENT '安全库存',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-物料维度表';

-- ---------- dim_product.sql ----------
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product (
	product_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '产品ID（主键，与源系统一致）',
	product_name VARCHAR ( 100 ) NOT NULL COMMENT '产品名称',
	category_l1 VARCHAR ( 50 ) COMMENT '一级品类',
	category_l2 VARCHAR ( 50 ) COMMENT '二级品类',
	category_l3 VARCHAR ( 50 ) COMMENT '三级品类',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-产品维度表';

-- ---------- dim_supplier.sql ----------
DROP TABLE IF EXISTS dim_supplier;
CREATE TABLE dim_supplier (
	supplier_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '供应商ID（主键，与源系统一致）',
	supplier_name VARCHAR ( 100 ) NOT NULL COMMENT '供应商名称',
	supply_category VARCHAR ( 50 ) COMMENT '供应品类',
	cooperation_grade VARCHAR ( 20 ) COMMENT '合作等级（A/B/C/D）',
	cooperation_status VARCHAR ( 20 ) COMMENT '合作状态（合作中/已终止）',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-供应商维度表';

-- ---------- dim_workshop.sql ----------
DROP TABLE IF EXISTS dim_workshop;
CREATE TABLE dim_workshop (
	workshop_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '车间ID（主键，与源系统一致）',
	workshop_name VARCHAR ( 50 ) NOT NULL COMMENT '车间名称',
	production_line VARCHAR ( 50 ) COMMENT '所属产线',
	workshop_type VARCHAR ( 20 ) COMMENT '车间类型（冲压/焊接/装配/涂装/加工）',
	capacity_per_day INT DEFAULT 0 COMMENT '日设计产能（件）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-车间维度表';

-- ---------- dwd_cost_detail.sql ----------
DROP TABLE IF EXISTS dwd_cost_detail;
CREATE TABLE dwd_cost_detail (
	voucher_id VARCHAR ( 32 ) COMMENT '凭证ID',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联dim_product）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID（关联dwd_produce_workorder_detail）',
	material_cost DECIMAL ( 12, 2 ) COMMENT '物料成本（元）',
	labor_cost DECIMAL ( 12, 2 ) COMMENT '人工成本（元）',
	mfg_cost DECIMAL ( 12, 2 ) COMMENT '制造费用（元）',
	total_cost DECIMAL ( 12, 2 ) COMMENT '总成本（元）',
	cost_month VARCHAR ( 7 ) COMMENT '成本月份（YYYY-MM）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	-- 主键必须包含分区列（MySQL 硬性要求）。这里的业务日期列是 cost_month（'YYYY-MM' 字符串，
	-- 字典序恰好等于时间序，所以可以直接作为 RANGE COLUMNS 的边界）。
	PRIMARY KEY ( voucher_id, cost_month ),
	INDEX idx_workorder_id ( workorder_id ),
	INDEX idx_product_id ( product_id ),
	INDEX idx_cost_month ( cost_month )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-成本明细事实表（按 cost_month 月度 RANGE 分区）'
PARTITION BY RANGE COLUMNS ( cost_month ) (
	PARTITION p202509 VALUES LESS THAN ( '2025-10' ),
	PARTITION p202510 VALUES LESS THAN ( '2025-11' ),
	PARTITION p202511 VALUES LESS THAN ( '2025-12' ),
	PARTITION p202512 VALUES LESS THAN ( '2026-01' ),
	PARTITION p202601 VALUES LESS THAN ( '2026-02' ),
	PARTITION p202602 VALUES LESS THAN ( '2026-03' ),
	PARTITION p202603 VALUES LESS THAN ( '2026-04' ),
	PARTITION p202604 VALUES LESS THAN ( '2026-05' ),
	PARTITION p202605 VALUES LESS THAN ( '2026-06' ),
	PARTITION p202606 VALUES LESS THAN ( '2026-07' ),
	PARTITION p202607 VALUES LESS THAN ( '2026-08' ),
	PARTITION p202608 VALUES LESS THAN ( '2026-09' ),
	PARTITION p202609 VALUES LESS THAN ( '2026-10' ),
	PARTITION p202610 VALUES LESS THAN ( '2026-11' ),
	PARTITION p202611 VALUES LESS THAN ( '2026-12' ),
	PARTITION p202612 VALUES LESS THAN ( '2027-01' ),
	PARTITION pmax    VALUES LESS THAN ( MAXVALUE )
);

-- ---------- dwd_equipment_runtime.sql ----------
DROP TABLE IF EXISTS dwd_equipment_runtime;
CREATE TABLE dwd_equipment_runtime (
	record_id VARCHAR ( 32 ) COMMENT '记录ID',
	equipment_id VARCHAR ( 32 ) COMMENT '设备ID（关联dim_equipment）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	record_date DATE COMMENT '记录日期',
	runtime_min INT COMMENT '实际运行分钟数',
	idle_min INT COMMENT '空闲分钟数',
	fault_min INT COMMENT '故障停机分钟数',
	maintain_min INT COMMENT '计划维护分钟数',
	total_min INT DEFAULT 1440 COMMENT '当日总分钟数',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	-- 主键必须包含分区列（MySQL 硬性要求）
	PRIMARY KEY ( record_id, record_date ),
	INDEX idx_record_date ( record_date ),
	INDEX idx_equipment_id ( equipment_id ),
	INDEX idx_workshop_id ( workshop_id )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-设备运行记录事实表（按 record_date 月度 RANGE 分区）'
PARTITION BY RANGE COLUMNS ( record_date ) (
	PARTITION p202509 VALUES LESS THAN ( '2025-10-01' ),
	PARTITION p202510 VALUES LESS THAN ( '2025-11-01' ),
	PARTITION p202511 VALUES LESS THAN ( '2025-12-01' ),
	PARTITION p202512 VALUES LESS THAN ( '2026-01-01' ),
	PARTITION p202601 VALUES LESS THAN ( '2026-02-01' ),
	PARTITION p202602 VALUES LESS THAN ( '2026-03-01' ),
	PARTITION p202603 VALUES LESS THAN ( '2026-04-01' ),
	PARTITION p202604 VALUES LESS THAN ( '2026-05-01' ),
	PARTITION p202605 VALUES LESS THAN ( '2026-06-01' ),
	PARTITION p202606 VALUES LESS THAN ( '2026-07-01' ),
	PARTITION p202607 VALUES LESS THAN ( '2026-08-01' ),
	PARTITION p202608 VALUES LESS THAN ( '2026-09-01' ),
	PARTITION p202609 VALUES LESS THAN ( '2026-10-01' ),
	PARTITION p202610 VALUES LESS THAN ( '2026-11-01' ),
	PARTITION p202611 VALUES LESS THAN ( '2026-12-01' ),
	PARTITION p202612 VALUES LESS THAN ( '2027-01-01' ),
	PARTITION pmax    VALUES LESS THAN ( MAXVALUE )
);

-- ---------- dwd_produce_workorder_detail.sql ----------
DROP TABLE IF EXISTS dwd_produce_workorder_detail;
CREATE TABLE dwd_produce_workorder_detail (
	workorder_id VARCHAR ( 32 ) COMMENT '工单号',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联dim_product）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	plan_qty INT COMMENT '计划产量',
	actual_qty INT COMMENT '实际产量',
	qualified_qty INT COMMENT '良品数量',
	defect_qty INT COMMENT '不良品数量',
	defect_type VARCHAR ( 50 ) COMMENT '主要不良类型',
	plan_start_date DATE COMMENT '计划开工日期',
	plan_end_date DATE COMMENT '计划完工日期',
	actual_start_date DATE COMMENT '实际开工日期',
	actual_end_date DATE COMMENT '实际完工日期',
	workorder_status VARCHAR ( 20 ) COMMENT '工单状态',
	labor_hours DECIMAL ( 10, 2 ) COMMENT '人工工时（小时）',
	material_loss DECIMAL ( 12, 2 ) COMMENT '物料损耗金额（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	-- 主键必须包含分区列（MySQL 硬性要求）
	PRIMARY KEY ( workorder_id, plan_start_date ),
	INDEX idx_plan_start_date ( plan_start_date ),
	INDEX idx_product_id ( product_id ),
	INDEX idx_workshop_id ( workshop_id ),
	INDEX idx_workorder_status ( workorder_status )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-生产工单明细事实表（按 plan_start_date 月度 RANGE 分区）'
PARTITION BY RANGE COLUMNS ( plan_start_date ) (
	PARTITION p202509 VALUES LESS THAN ( '2025-10-01' ),
	PARTITION p202510 VALUES LESS THAN ( '2025-11-01' ),
	PARTITION p202511 VALUES LESS THAN ( '2025-12-01' ),
	PARTITION p202512 VALUES LESS THAN ( '2026-01-01' ),
	PARTITION p202601 VALUES LESS THAN ( '2026-02-01' ),
	PARTITION p202602 VALUES LESS THAN ( '2026-03-01' ),
	PARTITION p202603 VALUES LESS THAN ( '2026-04-01' ),
	PARTITION p202604 VALUES LESS THAN ( '2026-05-01' ),
	PARTITION p202605 VALUES LESS THAN ( '2026-06-01' ),
	PARTITION p202606 VALUES LESS THAN ( '2026-07-01' ),
	PARTITION p202607 VALUES LESS THAN ( '2026-08-01' ),
	PARTITION p202608 VALUES LESS THAN ( '2026-09-01' ),
	PARTITION p202609 VALUES LESS THAN ( '2026-10-01' ),
	PARTITION p202610 VALUES LESS THAN ( '2026-11-01' ),
	PARTITION p202611 VALUES LESS THAN ( '2026-12-01' ),
	PARTITION p202612 VALUES LESS THAN ( '2027-01-01' ),
	PARTITION pmax    VALUES LESS THAN ( MAXVALUE )
);

-- ---------- dwd_sale_order_detail.sql ----------
DROP TABLE IF EXISTS dwd_sale_order_detail;
CREATE TABLE dwd_sale_order_detail (
	order_id VARCHAR ( 32 ) COMMENT '订单号',
	customer_id VARCHAR ( 32 ) COMMENT '客户ID（关联dim_customer）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联dim_product）',
	order_date DATE COMMENT '下单日期',
	order_amount DECIMAL ( 12, 2 ) COMMENT '订单含税总金额（元）',
	tax_amount DECIMAL ( 12, 2 ) COMMENT '税额（元）',
	discount_amount DECIMAL ( 12, 2 ) DEFAULT 0 COMMENT '优惠金额（元）',
	net_amount DECIMAL ( 12, 2 ) COMMENT '实付金额（元）',
	order_status VARCHAR ( 20 ) COMMENT '订单状态',
	delivery_date DATE COMMENT '实际发货日期',
	payment_date DATE COMMENT '回款日期',
	region VARCHAR ( 50 ) COMMENT '客户区域',
	quantity INT COMMENT '订购数量',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	-- 主键必须包含分区列（MySQL 硬性要求：每个唯一索引都要包含所有分区列）。
	-- order_id 本身仍是唯一的，这里只是把键变宽；注意不要再按 order_id 单独做 UPSERT（不会再冲突）。
	PRIMARY KEY ( order_id, order_date ),
	INDEX idx_order_date ( order_date ),
	INDEX idx_customer_id ( customer_id ),
	INDEX idx_product_id ( product_id ),
	INDEX idx_order_status ( order_status )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-销售订单明细事实表（按 order_date 月度 RANGE 分区）'
PARTITION BY RANGE COLUMNS ( order_date ) (
	PARTITION p202509 VALUES LESS THAN ( '2025-10-01' ),
	PARTITION p202510 VALUES LESS THAN ( '2025-11-01' ),
	PARTITION p202511 VALUES LESS THAN ( '2025-12-01' ),
	PARTITION p202512 VALUES LESS THAN ( '2026-01-01' ),
	PARTITION p202601 VALUES LESS THAN ( '2026-02-01' ),
	PARTITION p202602 VALUES LESS THAN ( '2026-03-01' ),
	PARTITION p202603 VALUES LESS THAN ( '2026-04-01' ),
	PARTITION p202604 VALUES LESS THAN ( '2026-05-01' ),
	PARTITION p202605 VALUES LESS THAN ( '2026-06-01' ),
	PARTITION p202606 VALUES LESS THAN ( '2026-07-01' ),
	PARTITION p202607 VALUES LESS THAN ( '2026-08-01' ),
	PARTITION p202608 VALUES LESS THAN ( '2026-09-01' ),
	PARTITION p202609 VALUES LESS THAN ( '2026-10-01' ),
	PARTITION p202610 VALUES LESS THAN ( '2026-11-01' ),
	PARTITION p202611 VALUES LESS THAN ( '2026-12-01' ),
	PARTITION p202612 VALUES LESS THAN ( '2027-01-01' ),
	PARTITION pmax    VALUES LESS THAN ( MAXVALUE )
);

-- ---------- dwd_stock_io_detail.sql ----------
DROP TABLE IF EXISTS dwd_stock_io_detail;
CREATE TABLE dwd_stock_io_detail (
	io_id VARCHAR ( 32 ) COMMENT '出入库记录ID',
	material_id VARCHAR ( 32 ) COMMENT '物料ID（关联dim_material）',
	warehouse_id VARCHAR ( 32 ) COMMENT '仓库ID',
	io_type VARCHAR ( 10 ) COMMENT '出入库类型（IN/OUT）',
	io_qty INT COMMENT '数量',
	io_amount DECIMAL ( 12, 2 ) COMMENT '总金额（元）',
	unit_price DECIMAL ( 12, 2 ) COMMENT '单价（元）',
	io_date DATE COMMENT '出入库日期',
	supplier_id VARCHAR ( 32 ) COMMENT '供应商ID（关联dim_supplier）',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID（关联dwd_produce_workorder_detail）',
	order_id VARCHAR ( 32 ) COMMENT '订单ID（关联dwd_sale_order_detail）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	-- 主键必须包含分区列（MySQL 硬性要求）
	PRIMARY KEY ( io_id, io_date ),
	INDEX idx_io_date ( io_date ),
	INDEX idx_material_id ( material_id ),
	INDEX idx_io_type ( io_type ),
	INDEX idx_workorder_id ( workorder_id ),
	INDEX idx_mat_wh_date ( material_id, warehouse_id, io_date ),
	INDEX idx_order_id ( order_id )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-出入库明细事实表（按 io_date 月度 RANGE 分区）'
PARTITION BY RANGE COLUMNS ( io_date ) (
	PARTITION p202509 VALUES LESS THAN ( '2025-10-01' ),
	PARTITION p202510 VALUES LESS THAN ( '2025-11-01' ),
	PARTITION p202511 VALUES LESS THAN ( '2025-12-01' ),
	PARTITION p202512 VALUES LESS THAN ( '2026-01-01' ),
	PARTITION p202601 VALUES LESS THAN ( '2026-02-01' ),
	PARTITION p202602 VALUES LESS THAN ( '2026-03-01' ),
	PARTITION p202603 VALUES LESS THAN ( '2026-04-01' ),
	PARTITION p202604 VALUES LESS THAN ( '2026-05-01' ),
	PARTITION p202605 VALUES LESS THAN ( '2026-06-01' ),
	PARTITION p202606 VALUES LESS THAN ( '2026-07-01' ),
	PARTITION p202607 VALUES LESS THAN ( '2026-08-01' ),
	PARTITION p202608 VALUES LESS THAN ( '2026-09-01' ),
	PARTITION p202609 VALUES LESS THAN ( '2026-10-01' ),
	PARTITION p202610 VALUES LESS THAN ( '2026-11-01' ),
	PARTITION p202611 VALUES LESS THAN ( '2026-12-01' ),
	PARTITION p202612 VALUES LESS THAN ( '2027-01-01' ),
	PARTITION pmax    VALUES LESS THAN ( MAXVALUE )
);

-- ---------- dwd_stock_snapshot.sql ----------
DROP TABLE IF EXISTS dwd_stock_snapshot;
CREATE TABLE dwd_stock_snapshot (
	snapshot_date DATE NOT NULL COMMENT '快照日期',
	material_id VARCHAR ( 32 ) NOT NULL COMMENT '物料ID（关联dim_material）',
	warehouse_id VARCHAR ( 32 ) NOT NULL COMMENT '仓库ID',
	stock_qty INT COMMENT '库存数量',
	stock_amount DECIMAL ( 16, 2 ) COMMENT '库存金额（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	-- 主键天然包含分区列 snapshot_date，无需调整
	PRIMARY KEY ( snapshot_date, material_id, warehouse_id ),
	INDEX idx_material_id ( material_id ),
	INDEX idx_warehouse_id ( warehouse_id )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-库存快照事实表（每日物料×仓库库存，按 snapshot_date 月度 RANGE 分区）'
PARTITION BY RANGE COLUMNS ( snapshot_date ) (
	PARTITION p202509 VALUES LESS THAN ( '2025-10-01' ),
	PARTITION p202510 VALUES LESS THAN ( '2025-11-01' ),
	PARTITION p202511 VALUES LESS THAN ( '2025-12-01' ),
	PARTITION p202512 VALUES LESS THAN ( '2026-01-01' ),
	PARTITION p202601 VALUES LESS THAN ( '2026-02-01' ),
	PARTITION p202602 VALUES LESS THAN ( '2026-03-01' ),
	PARTITION p202603 VALUES LESS THAN ( '2026-04-01' ),
	PARTITION p202604 VALUES LESS THAN ( '2026-05-01' ),
	PARTITION p202605 VALUES LESS THAN ( '2026-06-01' ),
	PARTITION p202606 VALUES LESS THAN ( '2026-07-01' ),
	PARTITION p202607 VALUES LESS THAN ( '2026-08-01' ),
	PARTITION p202608 VALUES LESS THAN ( '2026-09-01' ),
	PARTITION p202609 VALUES LESS THAN ( '2026-10-01' ),
	PARTITION p202610 VALUES LESS THAN ( '2026-11-01' ),
	PARTITION p202611 VALUES LESS THAN ( '2026-12-01' ),
	PARTITION p202612 VALUES LESS THAN ( '2027-01-01' ),
	PARTITION pmax    VALUES LESS THAN ( MAXVALUE )
);

-- ============================================================
-- dws_db（5 张表）
-- ============================================================
USE dws_db;

-- ---------- dws_cost_month.sql ----------
DROP TABLE IF EXISTS dws_cost_month;
CREATE TABLE dws_cost_month (
	stat_month VARCHAR ( 7 ) NOT NULL COMMENT '统计月份（YYYY-MM）',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	workshop_id VARCHAR ( 32 ) NOT NULL COMMENT '车间ID',
	material_cost DECIMAL ( 16, 2 ) COMMENT '物料成本总额',
	labor_cost DECIMAL ( 16, 2 ) COMMENT '人工成本总额',
	mfg_cost DECIMAL ( 16, 2 ) COMMENT '制造费用总额',
	total_cost DECIMAL ( 16, 2 ) COMMENT '总成本',
	unit_cost DECIMAL ( 12, 2 ) COMMENT '单位成本',
	cost_diff_rate DECIMAL ( 5, 2 ) COMMENT '成本差异率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_month, product_id, workshop_id ),
	INDEX idx_stat_month ( stat_month ),
	INDEX idx_product_id ( product_id ),
INDEX idx_workshop_id ( workshop_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-成本月汇总表';

-- ---------- dws_produce_day.sql ----------
DROP TABLE IF EXISTS dws_produce_day;
CREATE TABLE dws_produce_day (
	stat_date DATE NOT NULL COMMENT '统计日期',
	workshop_id VARCHAR ( 32 ) NOT NULL COMMENT '车间ID',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	plan_qty INT COMMENT '计划产量',
	actual_qty INT COMMENT '实际产量',
	qualified_qty INT COMMENT '良品数量',
	defect_qty INT COMMENT '不良品数量',
	labor_hours DECIMAL ( 12, 2 ) COMMENT '人工工时',
	oee_rate DECIMAL ( 5, 2 ) COMMENT 'OEE效率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, workshop_id, product_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_workshop_id ( workshop_id ),
INDEX idx_product_id ( product_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-生产日汇总表';

-- ---------- dws_sale_day.sql ----------
DROP TABLE IF EXISTS dws_sale_day;
CREATE TABLE dws_sale_day (
	stat_date DATE NOT NULL COMMENT '统计日期',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	customer_id VARCHAR ( 32 ) NOT NULL COMMENT '客户ID',
	region VARCHAR ( 50 ) COMMENT '区域',
	order_cnt INT COMMENT '订单数量',
	order_amt DECIMAL ( 16, 2 ) COMMENT '订单总金额',
	paid_amt DECIMAL ( 16, 2 ) COMMENT '回款金额',
	delivery_ontime_cnt INT COMMENT '按时交付订单数',
	delivery_cnt INT COMMENT '已交付订单数（分母：订单履约率 = 按时交付 ÷ 已交付）',
	return_amt DECIMAL ( 16, 2 ) COMMENT '退货金额',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, product_id, customer_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_product_id ( product_id ),
INDEX idx_customer_id ( customer_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-销售日汇总表';

-- ---------- dws_sale_month.sql ----------
DROP TABLE IF EXISTS dws_sale_month;
CREATE TABLE dws_sale_month (
	stat_month VARCHAR ( 7 ) NOT NULL COMMENT '统计月份（YYYY-MM）',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	customer_id VARCHAR ( 32 ) NOT NULL COMMENT '客户ID',
	region VARCHAR ( 50 ) COMMENT '区域',
	order_cnt INT COMMENT '订单数量',
	order_amt DECIMAL ( 16, 2 ) COMMENT '订单总金额',
	paid_amt DECIMAL ( 16, 2 ) COMMENT '回款金额',
	delivery_ontime_cnt INT COMMENT '按时交付订单数',
	return_amt DECIMAL ( 16, 2 ) COMMENT '退货金额',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_month, product_id, customer_id ),
	INDEX idx_stat_month ( stat_month ),
	INDEX idx_product_id ( product_id ),
INDEX idx_customer_id ( customer_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-销售月汇总表';

-- ---------- dws_stock_day.sql ----------
DROP TABLE IF EXISTS dws_stock_day;
CREATE TABLE dws_stock_day (
	stat_date DATE NOT NULL COMMENT '统计日期',
	material_id VARCHAR ( 32 ) NOT NULL COMMENT '物料ID',
	warehouse_id VARCHAR ( 32 ) NOT NULL COMMENT '仓库ID',
	stock_qty INT COMMENT '库存数量',
	stock_amt DECIMAL ( 16, 2 ) COMMENT '库存金额',
	in_qty INT COMMENT '入库数量',
	out_qty INT COMMENT '出库数量',
	turnover_days DECIMAL ( 10, 2 ) COMMENT '周转天数',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, material_id, warehouse_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_material_id ( material_id ),
INDEX idx_warehouse_id ( warehouse_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-库存日汇总表';

-- ============================================================
-- ads_db（6 张表）
-- ============================================================
USE ads_db;

-- ---------- ads_alert_warning.sql ----------
DROP TABLE IF EXISTS ads_alert_warning;
CREATE TABLE ads_alert_warning (
	alert_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '预警ID（主键）',
	alert_date DATE NOT NULL COMMENT '预警日期',
	alert_type VARCHAR ( 50 ) COMMENT '预警类型（营收缺口/产能不足/库存积压/不良超标/回款滞后）',
	alert_level VARCHAR ( 20 ) COMMENT '预警等级（高/中/低）',
	target_name VARCHAR ( 100 ) COMMENT '预警对象名称（产品/车间/客户等）',
	target_id VARCHAR ( 32 ) COMMENT '预警对象ID',
	current_value VARCHAR ( 100 ) COMMENT '当前值',
	threshold_value VARCHAR ( 100 ) COMMENT '阈值',
	alert_desc VARCHAR ( 255 ) COMMENT '预警描述',
	is_resolved TINYINT DEFAULT 0 COMMENT '是否已处理（1=是，0=否）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_alert_date ( alert_date ),
	INDEX idx_alert_type ( alert_type ),
	INDEX idx_alert_level ( alert_level ),
INDEX idx_is_resolved ( is_resolved ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-异常预警清单';

-- ---------- ads_boss_dashboard.sql ----------
DROP TABLE IF EXISTS ads_boss_dashboard;
CREATE TABLE ads_boss_dashboard (
	stat_date DATE PRIMARY KEY COMMENT '统计日期',
	total_revenue DECIMAL ( 16, 2 ) COMMENT '当日总营收',
	total_profit DECIMAL ( 16, 2 ) COMMENT '当日总利润',
	profit_rate DECIMAL ( 5, 2 ) COMMENT '利润率（%）',
	capacity_achieved DECIMAL ( 5, 2 ) COMMENT '产能达成率（%）',
	inventory_turnover DECIMAL ( 10, 2 ) COMMENT '库存周转天数',
	order_fulfill_rate DECIMAL ( 5, 2 ) COMMENT '订单履约率（%）',
	material_cost_ratio DECIMAL ( 5, 2 ) COMMENT '物料成本占比（%）',
	labor_cost_ratio DECIMAL ( 5, 2 ) COMMENT '人工成本占比（%）',
	mfg_cost_ratio DECIMAL ( 5, 2 ) COMMENT '制造费用占比（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-经营总览大屏';

-- ---------- ads_cost_profit.sql ----------
DROP TABLE IF EXISTS ads_cost_profit;
CREATE TABLE ads_cost_profit (
	stat_month VARCHAR ( 7 ) NOT NULL COMMENT '统计月份（YYYY-MM）',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	product_name VARCHAR ( 100 ) COMMENT '产品名称',
	workshop_id VARCHAR ( 32 ) NOT NULL COMMENT '车间ID',
	workshop_name VARCHAR ( 50 ) COMMENT '车间名称',
	material_cost DECIMAL ( 16, 2 ) COMMENT '物料成本',
	labor_cost DECIMAL ( 16, 2 ) COMMENT '人工成本',
	mfg_cost DECIMAL ( 16, 2 ) COMMENT '制造费用',
	total_cost DECIMAL ( 16, 2 ) COMMENT '总成本',
	unit_cost DECIMAL ( 12, 2 ) COMMENT '单位成本',
	sale_price DECIMAL ( 12, 2 ) COMMENT '销售均价',
	unit_profit DECIMAL ( 12, 2 ) COMMENT '单位毛利',
	profit_rate DECIMAL ( 5, 2 ) COMMENT '毛利率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_month, product_id, workshop_id ),
	INDEX idx_stat_month ( stat_month ),
	INDEX idx_product_id ( product_id ),
INDEX idx_workshop_id ( workshop_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-成本利润分析报表';

-- ---------- ads_produce_monitor.sql ----------
DROP TABLE IF EXISTS ads_produce_monitor;
CREATE TABLE ads_produce_monitor (
	stat_date DATE NOT NULL COMMENT '统计日期',
	workshop_id VARCHAR ( 32 ) NOT NULL COMMENT '车间ID',
	workshop_name VARCHAR ( 50 ) COMMENT '车间名称',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	product_name VARCHAR ( 100 ) COMMENT '产品名称',
	plan_qty INT COMMENT '计划产量',
	actual_qty INT COMMENT '实际产量',
	qualified_qty INT COMMENT '良品数量',
	defect_qty INT COMMENT '不良品数量',
	defect_type VARCHAR ( 50 ) COMMENT '主要不良类型',
	capacity_achieved DECIMAL ( 5, 2 ) COMMENT '产能达成率（%）',
	qualified_rate DECIMAL ( 5, 2 ) COMMENT '良品率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, workshop_id, product_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_workshop_id ( workshop_id ),
INDEX idx_product_id ( product_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-生产监控报表';

-- ---------- ads_sale_analysis.sql ----------
DROP TABLE IF EXISTS ads_sale_analysis;
CREATE TABLE ads_sale_analysis (
	stat_date DATE NOT NULL COMMENT '统计日期',
	customer_id VARCHAR ( 32 ) NOT NULL COMMENT '客户ID',
	customer_name VARCHAR ( 100 ) COMMENT '客户名称',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	product_name VARCHAR ( 100 ) COMMENT '产品名称',
	region VARCHAR ( 50 ) COMMENT '区域',
	order_cnt INT COMMENT '订单数',
	order_amt DECIMAL ( 16, 2 ) COMMENT '订单金额',
	paid_amt DECIMAL ( 16, 2 ) COMMENT '回款金额',
	return_amt DECIMAL ( 16, 2 ) COMMENT '退货金额',
	delivery_ontime_rate DECIMAL ( 5, 2 ) COMMENT '交付及时率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, customer_id, product_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_customer_id ( customer_id ),
	INDEX idx_product_id ( product_id ),
INDEX idx_region ( region ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-销售分析报表';

-- ---------- ads_stock_health.sql ----------
DROP TABLE IF EXISTS ads_stock_health;
CREATE TABLE ads_stock_health (
	stat_date DATE NOT NULL COMMENT '统计日期',
	material_id VARCHAR ( 32 ) NOT NULL COMMENT '物料ID',
	material_name VARCHAR ( 100 ) COMMENT '物料名称',
	warehouse_id VARCHAR ( 32 ) NOT NULL COMMENT '仓库ID',
	stock_qty INT COMMENT '库存数量',
	stock_amt DECIMAL ( 16, 2 ) COMMENT '库存金额',
	turnover_days DECIMAL ( 10, 2 ) COMMENT '周转天数',
	is_slow_moving TINYINT COMMENT '是否呆滞物料（1=是，0=否）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, material_id, warehouse_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_material_id ( material_id ),
INDEX idx_is_slow_moving ( is_slow_moving ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-库存健康度报表';

