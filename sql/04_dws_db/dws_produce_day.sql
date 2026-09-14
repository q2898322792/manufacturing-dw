DROP TABLE IF EXISTS dws_produce_day;
CREATE TABLE dws_produce_day (
	stat_date DATE NOT NULL COMMENT '统计日期',
	workshop_id VARCHAR ( 32 ) NOT NULL COMMENT '车间ID',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	plan_qty INT COMMENT '计划产量',
	actual_qty INT COMMENT '实际产量',
	qualified_qty INT COMMENT '良品数量',
	defect_qty INT COMMENT '不良品数量',
	labor_hours DECIMAL ( 12, 2 ) COMMENT '人工工时',
	oee_rate DECIMAL ( 5, 2 ) COMMENT 'OEE效率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, workshop_id, product_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_workshop_id ( workshop_id ),
INDEX idx_product_id ( product_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-生产日汇总表';