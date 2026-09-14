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
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-出入库明细事实表';