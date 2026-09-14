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