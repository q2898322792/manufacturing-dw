DROP TABLE IF EXISTS dwd_equipment_runtime;
CREATE TABLE dwd_equipment_runtime (
	record_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '记录ID（主键）',
	equipment_id VARCHAR ( 32 ) COMMENT '设备ID（关联dim_equipment）',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	record_date DATE COMMENT '记录日期',
	runtime_min INT COMMENT '实际运行分钟数',
	idle_min INT COMMENT '空闲分钟数',
	fault_min INT COMMENT '故障停机分钟数',
	maintain_min INT COMMENT '计划维护分钟数',
	total_min INT DEFAULT 1440 COMMENT '当日总分钟数',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_record_date ( record_date ),
	INDEX idx_equipment_id ( equipment_id ),
INDEX idx_workshop_id ( workshop_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-设备运行记录事实表';