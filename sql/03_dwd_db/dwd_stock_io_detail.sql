DROP TABLE IF EXISTS dwd_stock_io_detail;
CREATE TABLE dwd_stock_io_detail (
	io_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '出入库记录ID（主键）',
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
	INDEX idx_io_date ( io_date ),
	INDEX idx_material_id ( material_id ),
	INDEX idx_io_type ( io_type ),
	INDEX idx_workorder_id ( workorder_id ),
	INDEX idx_mat_wh_date ( material_id, warehouse_id, io_date ),
INDEX idx_order_id ( order_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-出入库明细事实表';