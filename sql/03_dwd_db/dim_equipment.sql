DROP TABLE IF EXISTS dim_equipment;
CREATE TABLE dim_equipment (
	equipment_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '设备ID（主键）',
	equipment_name VARCHAR ( 100 ) COMMENT '设备名称',
	workshop_id VARCHAR ( 32 ) COMMENT '车间ID（关联dim_workshop）',
	equipment_type VARCHAR ( 50 ) COMMENT '设备类型',
	purchase_date DATE COMMENT '采购日期',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-设备维度表';