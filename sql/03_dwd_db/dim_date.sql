DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date (
	date_key DATE PRIMARY KEY COMMENT '日期（主键）',
	YEAR INT COMMENT '年',
	QUARTER INT COMMENT '季度（1-4）',
	MONTH INT COMMENT '月份（1-12）',
	WEEK INT COMMENT '周数',
	DAY INT COMMENT '日（1-31）',
	is_workday TINYINT COMMENT '是否工作日（1=是，0=否）',
	create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间' 
) ENGINE = INNODB DEFAULT CHARSET = utf8mb4 COMMENT = 'DWD-日期维度表';

-- 说明：本表数据不再在此写死日期初始化；
--       由 step02_dwd_dimension.sql 按 ODS 各事实表的实际日期范围动态重建（TRUNCATE + 递归插入）。
