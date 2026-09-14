DROP TABLE IF EXISTS ods_erp_customer;
CREATE TABLE ods_erp_customer (
	customer_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '客户ID（主键）',
	customer_name VARCHAR ( 100 ) NOT NULL COMMENT '客户名称',
	region VARCHAR ( 50 ) COMMENT '所属区域',
	grade VARCHAR ( 20 ) COMMENT '客户等级',
	type VARCHAR ( 20 ) COMMENT '客户类型',
	industry VARCHAR ( 50 ) COMMENT '所属行业',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-客户维度表';