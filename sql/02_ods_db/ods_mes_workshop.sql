DROP TABLE IF EXISTS ods_mes_workshop;
CREATE TABLE ods_mes_workshop (
	workshop_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '车间ID（主键）',
	workshop_name VARCHAR ( 50 ) NOT NULL COMMENT '车间名称',
	production_line VARCHAR ( 50 ) COMMENT '所属产线',
	workshop_type VARCHAR ( 20 ) COMMENT '车间类型',
	capacity_per_day INT DEFAULT 0 COMMENT '日设计产能（件）',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-车间维度表';