SELECT '无效产品ID' AS 脏数据类型,COUNT(*) AS num FROM erp_db.sale_order WHERE product_id = 'INVALID_001'
UNION ALL
SELECT '空客户ID' AS 脏数据类型,COUNT(*) AS num FROM erp_db.sale_order WHERE customer_id IS NULL
UNION ALL
SELECT '异常金额' AS 脏数据类型,COUNT(*) AS num FROM erp_db.sale_order WHERE order_amount < 0 OR order_amount > 9999999
UNION ALL
SELECT '异常产量' AS 脏数据类型,COUNT(*) AS num FROM mes_db.produce_workorder WHERE actual_qty > plan_qty * 2;
