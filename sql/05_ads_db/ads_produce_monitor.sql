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