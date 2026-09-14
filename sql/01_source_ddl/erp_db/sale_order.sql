DROP TABLE IF EXISTS sale_order;
CREATE TABLE sale_order (
	order_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '订单号（主键）',
	customer_id VARCHAR ( 32 ) COMMENT '客户ID（关联customer表）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联product表）',
	order_date DATE COMMENT '下单日期',
	order_amount DECIMAL ( 12, 2 ) COMMENT '订单含税总金额（元）',
	tax_amount DECIMAL ( 12, 2 ) COMMENT '税额（元）',
	discount_amount DECIMAL ( 12, 2 ) DEFAULT 0 COMMENT '优惠金额（元）',
	net_amount DECIMAL ( 12, 2 ) COMMENT '实付金额（元）',
	order_status VARCHAR ( 20 ) COMMENT '订单状态（已提交/已发货/已完成/已取消/已作废）',
	delivery_date DATE COMMENT '实际发货日期',
	payment_date DATE COMMENT '回款日期',
	region VARCHAR ( 50 ) COMMENT '客户区域（冗余字段，便于区域分析）',
	quantity INT COMMENT '订购数量',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_order_date ( order_date ),
	INDEX idx_customer_id ( customer_id ),
	INDEX idx_product_id ( product_id ),
INDEX idx_order_status ( order_status ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = '销售订单事实表';