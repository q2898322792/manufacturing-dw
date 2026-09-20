DROP TABLE IF EXISTS ods_mes_equipment_runtime;
CREATE TABLE ods_mes_equipment_runtime (
	record_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '记录ID（主键）',
	equipment_id VARCHAR ( 32 ) COMMENT '设备ID',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID',
	record_date DATE COMMENT '记录日期',
	runtime_min INT COMMENT '实际运行分钟数',
	idle_min INT COMMENT '空闲分钟数',
	fault_min INT COMMENT '故障停机分钟数',
	maintain_min INT COMMENT '计划维护分钟数',
	total_min INT DEFAULT 1440 COMMENT '当日总分钟数',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间',
INDEX idx_record_date ( record_date )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-设备运行记录事实表';