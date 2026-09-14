DROP TABLE IF EXISTS ads_cost_profit;
CREATE TABLE ads_cost_profit (
	stat_month VARCHAR ( 7 ) NOT NULL COMMENT '统计月份（YYYY-MM）',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	product_name VARCHAR ( 100 ) COMMENT '产品名称',
	workshop_id VARCHAR ( 32 ) NOT NULL COMMENT '车间ID',
	workshop_name VARCHAR ( 50 ) COMMENT '车间名称',
	material_cost DECIMAL ( 16, 2 ) COMMENT '物料成本',
	labor_cost DECIMAL ( 16, 2 ) COMMENT '人工成本',
	mfg_cost DECIMAL ( 16, 2 ) COMMENT '制造费用',
	total_cost DECIMAL ( 16, 2 ) COMMENT '总成本',
	unit_cost DECIMAL ( 12, 2 ) COMMENT '单位成本',
	sale_price DECIMAL ( 12, 2 ) COMMENT '销售均价',
	unit_profit DECIMAL ( 12, 2 ) COMMENT '单位毛利',
	profit_rate DECIMAL ( 5, 2 ) COMMENT '毛利率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_month, product_id, workshop_id ),
	INDEX idx_stat_month ( stat_month ),
	INDEX idx_product_id ( product_id ),
INDEX idx_workshop_id ( workshop_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-成本利润分析报表';