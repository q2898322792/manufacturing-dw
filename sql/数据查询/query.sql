 -- 1. 查看各表数据量
SELECT 'customer' AS 表名, COUNT(*) AS 行数 FROM erp_db.customer
UNION ALL
SELECT 'product', COUNT(*) FROM erp_db.product
UNION ALL
SELECT 'material', COUNT(*) FROM erp_db.material
UNION ALL
SELECT 'sale_order', COUNT(*) FROM erp_db.sale_order
UNION ALL
SELECT 'cost_voucher', COUNT(*) FROM erp_db.cost_voucher
UNION ALL
SELECT 'produce_workorder', COUNT(*) FROM mes_db.produce_workorder
UNION ALL
SELECT 'equipment_runtime', COUNT(*) FROM mes_db.equipment_runtime
UNION ALL
SELECT 'supplier', COUNT(*) FROM wms_db.supplier
UNION ALL
SELECT 'stock_io_detail', COUNT(*) FROM wms_db.stock_io_detail
UNION ALL
SELECT 'stock_snapshot', COUNT(*) FROM wms_db.stock_snapshot;