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