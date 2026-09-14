DROP TABLE IF EXISTS ads_boss_dashboard;
CREATE TABLE ads_boss_dashboard (
	stat_date DATE PRIMARY KEY COMMENT '统计日期',
	total_revenue DECIMAL ( 16, 2 ) COMMENT '当日总营收',
	total_profit DECIMAL ( 16, 2 ) COMMENT '当日总利润',
	profit_rate DECIMAL ( 5, 2 ) COMMENT '利润率（%）',
	capacity_achieved DECIMAL ( 5, 2 ) COMMENT '产能达成率（%）',
	inventory_turnover DECIMAL ( 10, 2 ) COMMENT '库存周转天数',
	order_fulfill_rate DECIMAL ( 5, 2 ) COMMENT '订单履约率（%）',
	material_cost_ratio DECIMAL ( 5, 2 ) COMMENT '物料成本占比（%）',
	labor_cost_ratio DECIMAL ( 5, 2 ) COMMENT '人工成本占比（%）',
	mfg_cost_ratio DECIMAL ( 5, 2 ) COMMENT '制造费用占比（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-经营总览大屏';