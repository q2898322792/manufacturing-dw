DROP TABLE IF EXISTS dim_workshop;
CREATE TABLE dim_workshop (
	workshop_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '车间ID（主键，与源系统一致）',
	workshop_name VARCHAR ( 50 ) NOT NULL COMMENT '车间名称',
	production_line VARCHAR ( 50 ) COMMENT '所属产线',
	workshop_type VARCHAR ( 20 ) COMMENT '车间类型（冲压/焊接/装配/涂装/加工）',
	capacity_per_day INT DEFAULT 0 COMMENT '日设计产能（件）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-车间维度表';