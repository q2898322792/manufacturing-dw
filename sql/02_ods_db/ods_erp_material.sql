DROP TABLE IF EXISTS ods_erp_material;
CREATE TABLE ods_erp_material (
	material_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '物料ID（主键）',
	material_name VARCHAR ( 100 ) NOT NULL COMMENT '物料名称',
	category VARCHAR ( 50 ) COMMENT '物料大类（原材料/辅料/半成品/成品）',
	sub_category VARCHAR ( 50 ) COMMENT '物料子类（电子件/结构件/塑胶件/包材/五金）',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位（个/套/米/公斤）',
	safety_stock INT DEFAULT 0 COMMENT '安全库存',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	source_system VARCHAR ( 20 ) DEFAULT 'erp' COMMENT '来源系统',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-物料维度表';