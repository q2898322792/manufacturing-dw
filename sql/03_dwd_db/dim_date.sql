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
TRUNCATE TABLE dim_date;
INSERT INTO dim_date ( date_key, YEAR, QUARTER, MONTH, WEEK, DAY, is_workday ) WITH RECURSIVE date_range AS (
	SELECT
		DATE( '2025-09-01' ) AS dt UNION ALL
	SELECT
		DATE_ADD( dt, INTERVAL 1 DAY ) 
	FROM
		date_range 
	WHERE
		dt < DATE( '2026-07-31' ) 
	) SELECT
	dt,
	YEAR ( dt ),
	QUARTER ( dt ),
	MONTH ( dt ),
	WEEK ( dt, 1 ),
	DAY ( dt ),
CASE
		
		WHEN DAYOFWEEK( dt ) IN ( 1, 7 ) THEN
		0 ELSE 1 
	END 
FROM
	date_range;