DROP TABLE IF EXISTS ads_alert_warning;
CREATE TABLE ads_alert_warning (
	alert_id VARCHAR ( 32 ) PRIMARY KEY COMMENT '预警ID（主键）',
	alert_date DATE NOT NULL COMMENT '预警日期',
	alert_type VARCHAR ( 50 ) COMMENT '预警类型（营收缺口/产能不足/库存积压/不良超标/回款滞后）',
	alert_level VARCHAR ( 20 ) COMMENT '预警等级（高/中/低）',
	target_name VARCHAR ( 100 ) COMMENT '预警对象名称（产品/车间/客户等）',
	target_id VARCHAR ( 32 ) COMMENT '预警对象ID',
	current_value VARCHAR ( 100 ) COMMENT '当前值',
	threshold_value VARCHAR ( 100 ) COMMENT '阈值',
	alert_desc VARCHAR ( 255 ) COMMENT '预警描述',
	is_resolved TINYINT DEFAULT 0 COMMENT '是否已处理（1=是，0=否）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
	update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
	INDEX idx_alert_date ( alert_date ),
	INDEX idx_alert_type ( alert_type ),
	INDEX idx_alert_level ( alert_level ),
INDEX idx_is_resolved ( is_resolved ) 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'ADS-异常预警清单';