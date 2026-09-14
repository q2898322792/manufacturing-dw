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
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-库存快照事实表';