DROP TABLE IF EXISTS ods_erp_cost_voucher;
CREATE TABLE ods_erp_cost_voucher (
	voucher_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '凭证ID（主键）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID',
	material_cost DECIMAL ( 12, 2 ) COMMENT '物料成本（元）',
	labor_cost DECIMAL ( 12, 2 ) COMMENT '人工成本（元）',
	mfg_cost DECIMAL ( 12, 2 ) COMMENT '制造费用（元）',
	total_cost DECIMAL ( 12, 2 ) COMMENT '总成本（元）',
	cost_month VARCHAR ( 7 ) COMMENT '成本月份（YYYY-MM）',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-成本凭证事实表';