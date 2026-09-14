DROP TABLE IF EXISTS dws_sale_day;
CREATE TABLE dws_sale_day (
	stat_date DATE NOT NULL COMMENT '统计日期',
	product_id VARCHAR ( 32 ) NOT NULL COMMENT '产品ID',
	customer_id VARCHAR ( 32 ) NOT NULL COMMENT '客户ID',
	region VARCHAR ( 50 ) COMMENT '区域',
	order_cnt INT COMMENT '订单数量',
	order_amt DECIMAL ( 16, 2 ) COMMENT '订单总金额',
	paid_amt DECIMAL ( 16, 2 ) COMMENT '回款金额',
	delivery_ontime_cnt INT COMMENT '按时交付订单数',
	delivery_cnt INT COMMENT '已交付订单数（分母：订单履约率 = 按时交付 ÷ 已交付）',
	return_amt DECIMAL ( 16, 2 ) COMMENT '退货金额',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	PRIMARY KEY ( stat_date, product_id, customer_id ),
	INDEX idx_stat_date ( stat_date ),
	INDEX idx_product_id ( product_id ),
INDEX idx_customer_id ( customer_id ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWS-销售日汇总表';