DROP TABLE IF EXISTS dwd_cost_detail;
CREATE TABLE dwd_cost_detail (
	voucher_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '凭证ID（主键）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联dim_product）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	workorder_id VARCHAR ( 32 ) COMMENT '工单ID（关联dwd_produce_workorder_detail）',
	material_cost DECIMAL ( 12, 2 ) COMMENT '物料成本（元）',
	labor_cost DECIMAL ( 12, 2 ) COMMENT '人工成本（元）',
	mfg_cost DECIMAL ( 12, 2 ) COMMENT '制造费用（元）',
	total_cost DECIMAL ( 12, 2 ) COMMENT '总成本（元）',
	cost_month VARCHAR ( 7 ) COMMENT '成本月份（YYYY-MM）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_workorder_id ( workorder_id ),
	INDEX idx_product_id ( product_id ),
INDEX idx_cost_month ( cost_month ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-成本明细事实表';