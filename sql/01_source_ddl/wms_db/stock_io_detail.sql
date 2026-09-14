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