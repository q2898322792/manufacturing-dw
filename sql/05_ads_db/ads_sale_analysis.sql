DROP TABLE IF EXISTS ads_sale_analysis;
CREATE TABLE ads_sale_analysis (
	stat_date DATE NOT NULL COMMENT '统计日期',
	customer_id VARCHAR ( 32 ) NOT NULL COMMENT '客户ID',
	customer_name VARCHAR ( 100 ) COMMENT '客户名称',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	product_name VARCHAR ( 100 ) COMMENT '产品名称',
	region VARCHAR ( 50 ) COMMENT '区域',
	order_cnt INT COMMENT '订单数',
	order_amt DECIMAL ( 16, 2 ) COMMENT '订单金额',
	paid_amt DECIMAL ( 16, 2 ) COMMENT '回款金额',
	return_amt DECIMAL ( 16, 2 ) COMMENT '退货金额',
	delivery_ontime_rate DECIMAL ( 5, 2 ) COMMENT '交付及时率（%）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, customer_id, product_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_customer_id ( customer_id ),
	INDEX idx_product_id ( product_id ),
INDEX idx_region ( region ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-销售分析报表';