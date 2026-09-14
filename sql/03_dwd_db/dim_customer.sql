DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
	customer_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '客户ID（主键，与源系统一致）',
	customer_name VARCHAR ( 100 ) NOT NULL COMMENT '客户名称',
	region VARCHAR ( 50 ) COMMENT '所属区域',
	grade VARCHAR ( 20 ) COMMENT '客户等级（A/B/C/D）',
	type VARCHAR ( 20 ) COMMENT '客户类型（企业/个人/政府）',
	industry VARCHAR ( 50 ) COMMENT '所属行业',
	contact_person VARCHAR ( 50 ) COMMENT '联系人',
	contact_phone VARCHAR ( 20 ) COMMENT '联系电话',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-客户维度表';