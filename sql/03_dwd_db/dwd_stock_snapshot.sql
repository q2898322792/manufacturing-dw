DROP TABLE IF EXISTS dwd_stock_snapshot;
CREATE TABLE dwd_stock_snapshot (
	snapshot_date DATE NOT NULL COMMENT '快照日期',
	material_id VARCHAR ( 32 ) NOT NULL COMMENT '物料ID（关联dim_material）',
	warehouse_id VARCHAR ( 32 ) NOT NULL COMMENT '仓库ID',
	stock_qty INT COMMENT '库存数量',
	stock_amount DECIMAL ( 16, 2 ) COMMENT '库存金额（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( snapshot_date, material_id, warehouse_id ),
	INDEX idx_material_id ( material_id ),
	INDEX idx_warehouse_id ( warehouse_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-库存快照事实表（每日物料×仓库库存）';
