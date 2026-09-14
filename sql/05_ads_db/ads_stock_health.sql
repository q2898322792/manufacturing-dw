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