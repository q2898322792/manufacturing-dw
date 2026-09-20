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
