DROP TABLE IF EXISTS dim_supplier;
CREATE TABLE dim_supplier (
	supplier_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '供应商ID（主键，与源系统一致）',
	supplier_name VARCHAR ( 100 ) NOT NULL COMMENT '供应商名称',
	supply_category VARCHAR ( 50 ) COMMENT '供应品类',
	cooperation_grade VARCHAR ( 20 ) COMMENT '合作等级（A/B/C/D）',
	cooperation_status VARCHAR ( 20 ) COMMENT '合作状态（合作中/已终止）',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-供应商维度表';