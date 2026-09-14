DROP TABLE IF EXISTS product;
CREATE TABLE product (
	product_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '产品ID（主键）',
	product_name VARCHAR ( 100 ) NOT NULL COMMENT '产品名称',
	category_l1 VARCHAR ( 50 ) COMMENT '一级品类',
	category_l2 VARCHAR ( 50 ) COMMENT '二级品类',
	category_l3 VARCHAR ( 50 ) COMMENT '三级品类',
	spec VARCHAR ( 100 ) COMMENT '规格型号',
	unit VARCHAR ( 10 ) COMMENT '计量单位（台/套/个/米）',
	standard_cost DECIMAL ( 12, 2 ) COMMENT '标准成本（元）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '产品维度表';