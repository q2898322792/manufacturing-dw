DROP TABLE IF EXISTS ods_erp_sale_order;
CREATE TABLE ods_erp_sale_order (
	order_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '订单号（主键）',
	customer_id VARCHAR ( 32 ) COMMENT '客户ID',
	product_id VARCHAR ( 32 ) COMMENT '产品ID',
	order_date DATE COMMENT '下单日期',
	order_amount DECIMAL ( 12, 2 ) COMMENT '订单含税总金额（元）',
	tax_amount DECIMAL ( 12, 2 ) COMMENT '税额（元）',
	discount_amount DECIMAL ( 12, 2 ) DEFAULT 0 COMMENT '优惠金额（元）',
	net_amount DECIMAL ( 12, 2 ) COMMENT '实付金额（元）',
	order_status VARCHAR ( 20 ) COMMENT '订单状态（已提交/已发货/已完成/已取消/已作废）',
	delivery_date DATE COMMENT '实际发货日期',
	payment_date DATE COMMENT '回款日期',
	region VARCHAR ( 50 ) COMMENT '客户区域',
	quantity INT COMMENT '订购数量',
	create_time DATETIME COMMENT '源系统创建时间',
	update_time DATETIME COMMENT '源系统更新时间',
etl_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL同步时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ODS-销售订单事实表';