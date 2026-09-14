DROP TABLE IF EXISTS dim_material;
CREATE TABLE dim_material (
	material_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '物料ID（主键，与源系统一致）',
	material_name VARCHAR ( 100 ) NOT NULL COMMENT '物料名称',
	category VARCHAR ( 50 ) COMMENT '物料大类（原材料/辅料/半成品/成品）',
	sub_category VARCHAR ( 50 ) COMMENT '物料子类（电子件/结构件/塑胶件/包材/五金）',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位',
	safety_stock INT DEFAULT 0 COMMENT '安全库存',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-物料维度表';