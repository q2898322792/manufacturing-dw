DROP TABLE IF EXISTS dws_cost_month;
CREATE TABLE dws_cost_month (
	stat_month VARCHAR ( 7 ) NOT NULL COMMENT '统计月份（YYYY-MM）',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	workshop_id VARCHAR ( 32 ) NOT NULL COMMENT '车间ID',
	material_cost DECIMAL ( 16, 2 ) COMMENT '物料成本总额',
	labor_cost DECIMAL ( 16, 2 ) COMMENT '人工成本总额',
	mfg_cost DECIMAL ( 16, 2 ) COMMENT '制造费用总额',
	total_cost DECIMAL ( 16, 2 ) COMMENT '总成本',
	unit_cost DECIMAL ( 12, 2 ) COMMENT '单位成本',
	cost_diff_rate DECIMAL ( 5, 2 ) COMMENT '成本差异率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_month, product_id, workshop_id ),
	INDEX idx_stat_month ( stat_month ),
	INDEX idx_product_id ( product_id ),
INDEX idx_workshop_id ( workshop_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-成本月汇总表';