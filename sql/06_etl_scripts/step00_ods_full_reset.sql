-- ============================================================
-- step00_ods_full_reset.sql（ODS 全量重建开关 · 手动执行，不在每日调度链里）
-- ============================================================
-- 【什么时候必须用】
--   当源库被"全量重建"过（例如重新跑了 generate_fake_data.py：主键全换、update_time 全是新的），
--   必须先把 ODS 清空并重置水位表。否则 step01 的"增量同步"会把这批新数据
--   当作增量【追加】进 ODS，结果是 ODS = 老数据 + 新数据。
--
--   2026-09-10 的 ETL 故障就是这个问题：源表 100 万订单 + 重新生成的 100 万订单
--   同时留在 ODS（2,000,025 行），DWD 重建量翻倍，把 C 盘写满，
--   最终 step03 报 (1114, "The table 'dwd_stock_io_detail' is full")。
--
-- 【执行顺序】
--   step00（本脚本） → step01 → step02 → step03 → step04 → step05
--
-- 【注意】
--   不要把它加进 etl_scheduler.py 的 ETL_STEPS，否则每天调度都会清空 ODS。
--   日常增量（源表只是新增几天的数据）不需要执行本脚本。
-- ============================================================

TRUNCATE TABLE ods_db.ods_erp_customer;
TRUNCATE TABLE ods_db.ods_erp_product;
TRUNCATE TABLE ods_db.ods_erp_material;
TRUNCATE TABLE ods_db.ods_erp_sale_order;
TRUNCATE TABLE ods_db.ods_erp_cost_voucher;
TRUNCATE TABLE ods_db.ods_mes_workshop;
TRUNCATE TABLE ods_db.ods_mes_workorder;
TRUNCATE TABLE ods_db.ods_mes_equipment_runtime;
TRUNCATE TABLE ods_db.ods_wms_supplier;
TRUNCATE TABLE ods_db.ods_wms_stock_io;
TRUNCATE TABLE ods_db.ods_wms_stock_snapshot;
-- 水位表清空后，step01 会自动重新初始化为 1970-01-01 并执行全量同步
TRUNCATE TABLE ods_db.etl_watermark;
