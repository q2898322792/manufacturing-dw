DROP TABLE IF EXISTS dwd_sale_order_detail;
CREATE TABLE dwd_sale_order_detail (
	order_id VARCHAR ( 32 ) COMMENT '订单号',
	customer_id VARCHAR ( 32 ) COMMENT '客户ID（关联dim_customer）',
	product_id VARCHAR ( 32 ) COMMENT '产品ID（关联dim_product）',
	order_date DATE COMMENT '下单日期',
	order_amount DECIMAL ( 12, 2 ) COMMENT '订单含税总金额（元）',
	tax_amount DECIMAL ( 12, 2 ) COMMENT '税额（元）',
	discount_amount DECIMAL ( 12, 2 ) DEFAULT 0 COMMENT '优惠金额（元）',
	net_amount DECIMAL ( 12, 2 ) COMMENT '实付金额（元）',
	order_status VARCHAR ( 20 ) COMMENT '订单状态',
	delivery_date DATE COMMENT '实际发货日期',
	payment_date DATE COMMENT '回款日期',
	region VARCHAR ( 50 ) COMMENT '客户区域',
	quantity INT COMMENT '订购数量',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	-- 主键必须包含分区列（MySQL 硬性要求：每个唯一索引都要包含所有分区列）。
	-- order_id 本身仍是唯一的，这里只是把键变宽；注意不要再按 order_id 单独做 UPSERT（不会再冲突）。
	PRIMARY KEY ( order_id, order_date ),
	INDEX idx_order_date ( order_date ),
	INDEX idx_customer_id ( customer_id ),
	INDEX idx_product_id ( product_id ),
	INDEX idx_order_status ( order_status )
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-销售订单明细事实表（按 order_date 月度 RANGE 分区）'
PARTITION BY RANGE COLUMNS ( order_date ) (
	PARTITION p202509 VALUES LESS THAN ( '2025-10-01' ),
	PARTITION p202510 VALUES LESS THAN ( '2025-11-01' ),
	PARTITION p202511 VALUES LESS THAN ( '2025-12-01' ),
	PARTITION p202512 VALUES LESS THAN ( '2026-01-01' ),
	PARTITION p202601 VALUES LESS THAN ( '2026-02-01' ),
	PARTITION p202602 VALUES LESS THAN ( '2026-03-01' ),
	PARTITION p202603 VALUES LESS THAN ( '2026-04-01' ),
	PARTITION p202604 VALUES LESS THAN ( '2026-05-01' ),
	PARTITION p202605 VALUES LESS THAN ( '2026-06-01' ),
	PARTITION p202606 VALUES LESS THAN ( '2026-07-01' ),
	PARTITION p202607 VALUES LESS THAN ( '2026-08-01' ),
	PARTITION p202608 VALUES LESS THAN ( '2026-09-01' ),
	PARTITION p202609 VALUES LESS THAN ( '2026-10-01' ),
	PARTITION p202610 VALUES LESS THAN ( '2026-11-01' ),
	PARTITION p202611 VALUES LESS THAN ( '2026-12-01' ),
	PARTITION p202612 VALUES LESS THAN ( '2027-01-01' ),
	PARTITION pmax    VALUES LESS THAN ( MAXVALUE )
);
