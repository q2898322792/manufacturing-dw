DROP TABLE IF EXISTS dwd_produce_workorder_detail;
CREATE TABLE dwd_produce_workorder_detail (
	workorder_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '工单号（主键）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联dim_product）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	plan_qty INT COMMENT '计划产量',
	actual_qty INT COMMENT '实际产量',
	qualified_qty INT COMMENT '良品数量',
	defect_qty INT COMMENT '不良品数量',
	defect_type VARCHAR ( 50 ) COMMENT '主要不良类型',
	plan_start_date DATE COMMENT '计划开工日期',
	plan_end_date DATE COMMENT '计划完工日期',
	actual_start_date DATE COMMENT '实际开工日期',
	actual_end_date DATE COMMENT '实际完工日期',
	workorder_status VARCHAR ( 20 ) COMMENT '工单状态',
	labor_hours DECIMAL ( 10, 2 ) COMMENT '人工工时（小时）',
	material_loss DECIMAL ( 12, 2 ) COMMENT '物料损耗金额（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_plan_start_date ( plan_start_date ),
	INDEX idx_product_id ( product_id ),
	INDEX idx_workshop_id ( workshop_id ),
INDEX idx_workorder_status ( workorder_status ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-生产工单明细事实表';