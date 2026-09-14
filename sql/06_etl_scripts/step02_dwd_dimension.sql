-- ============================================================
-- step02_dwd_dimension.sql（维度层重建 · 幂等版）
-- ============================================================
-- 策略：ODS 已通过 step01 做增量 UPSERT，DWD 维度表采用“每日全量重建”：
--   TRUNCATE + 从 ODS 取每个业务主键的最新版本插入，保证与 ODS 完全一致。
--
--  修复/优化点：
--   1. 去掉对 USE 语句的依赖，所有表名一律带库名前缀（dwd_db.xxx），
--      任何执行方式（调度器逐条执行 / 客户端整文件执行）都不会报
--      “No database selected / 未选择数据库(1046)”；
--   2. 每条 INSERT 前不再夹带会粘连到语句上的注释，改为独立成行注释；
--   3. ROW_NUMBER 去重只保留每个业务主键 update_time 最新的一行，
--      防止 ODS 偶发存在同主键多版本时把维度灌重；
--   4. 可重复执行：重复运行只是把维度表重建为相同内容，不报错、不膨胀。
--
--  说明：本文件只重建 5 张慢变化率很低的维度表；
--        dim_date / dim_equipment 等由建表脚本单独初始化，不在此重建。
-- ============================================================

-- 1. 清空 5 张维度表（全量重建前先清空）
TRUNCATE TABLE dwd_db.dim_customer;
TRUNCATE TABLE dwd_db.dim_product;
TRUNCATE TABLE dwd_db.dim_material;
TRUNCATE TABLE dwd_db.dim_supplier;
TRUNCATE TABLE dwd_db.dim_workshop;

-- 2. 客户维度（取每个 customer_id 的最新记录）
-- 【名称唯一化】模拟数据里公司名是从有限候选池随机抽取的：300 个客户只有 56 个不同名称
--   （"中国通号科技集团" 对应 10 个不同 customer_id）。不处理的话，看板按 customer_name
--   排行时会把多个客户合并成一组，所谓"客户排行"其实只有 56 组、且第一名是 10 个客户之和。
--   这里对重名的客户加 (序号) 后缀 —— 中国通号科技集团(1) ~ 中国通号科技集团(10)，
--   名称本来就唯一的客户保持原样不加后缀。
INSERT INTO dwd_db.dim_customer
    (customer_id, customer_name, region, grade, type, industry,
     contact_person, contact_phone)
SELECT
    t.customer_id,
    CASE WHEN t.name_cnt > 1
         THEN CONCAT(t.customer_name, '(',
                     ROW_NUMBER() OVER (PARTITION BY t.customer_name ORDER BY t.customer_id), ')')
         ELSE t.customer_name
    END AS customer_name,
    t.region, t.grade, t.type, t.industry, t.contact_person, t.contact_phone
FROM (
    SELECT customer_id, customer_name, region, grade, type, industry,
           contact_person, contact_phone,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY update_time DESC, etl_time DESC) AS rn,
           COUNT(*)     OVER (PARTITION BY customer_name) AS name_cnt
    FROM ods_db.ods_erp_customer
) t
WHERE t.rn = 1;

-- 3. 产品维度（取每个 product_id 的最新记录）
-- 【名称唯一化】同上：200 个产品只有 59 个不同名称（"工业相机" 对应 7 个不同 product_id）。
INSERT INTO dwd_db.dim_product
    (product_id, product_name, category_l1, category_l2, category_l3,
     spec, unit, standard_cost)
SELECT
    t.product_id,
    CASE WHEN t.name_cnt > 1
         THEN CONCAT(t.product_name, '(',
                     ROW_NUMBER() OVER (PARTITION BY t.product_name ORDER BY t.product_id), ')')
         ELSE t.product_name
    END AS product_name,
    t.category_l1, t.category_l2, t.category_l3, t.spec, t.unit, t.standard_cost
FROM (
    SELECT product_id, product_name, category_l1, category_l2, category_l3,
           spec, unit, standard_cost,
           ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY update_time DESC, etl_time DESC) AS rn,
           COUNT(*)     OVER (PARTITION BY product_name) AS name_cnt
    FROM ods_db.ods_erp_product
) t
WHERE t.rn = 1;

-- 4. 物料维度（取每个 material_id 的最新记录）
-- 【名称唯一化】同上：200 个物料只有 59 个不同名称。
INSERT INTO dwd_db.dim_material
    (material_id, material_name, category, sub_category, spec, unit,
     safety_stock, standard_cost)
SELECT
    t.material_id,
    CASE WHEN t.name_cnt > 1
         THEN CONCAT(t.material_name, '(',
                     ROW_NUMBER() OVER (PARTITION BY t.material_name ORDER BY t.material_id), ')')
         ELSE t.material_name
    END AS material_name,
    t.category, t.sub_category, t.spec, t.unit, t.safety_stock, t.standard_cost
FROM (
    SELECT material_id, material_name, category, sub_category, spec, unit,
           safety_stock, standard_cost,
           ROW_NUMBER() OVER (PARTITION BY material_id ORDER BY update_time DESC, etl_time DESC) AS rn,
           COUNT(*)     OVER (PARTITION BY material_name) AS name_cnt
    FROM ods_db.ods_erp_material
) t
WHERE t.rn = 1;

-- 5. 供应商维度（取每个 supplier_id 的最新记录）
INSERT INTO dwd_db.dim_supplier
    (supplier_id, supplier_name, supply_category, cooperation_grade,
     cooperation_status, contact_person, contact_phone)
SELECT supplier_id, supplier_name, supply_category, cooperation_grade,
       cooperation_status, contact_person, contact_phone
FROM (
    SELECT supplier_id, supplier_name, supply_category, cooperation_grade,
           cooperation_status, contact_person, contact_phone,
           ROW_NUMBER() OVER (PARTITION BY supplier_id ORDER BY update_time DESC, etl_time DESC) AS rn
    FROM ods_db.ods_wms_supplier
) t
WHERE rn = 1;

-- 6. 车间维度（取每个 workshop_id 的最新记录）
INSERT INTO dwd_db.dim_workshop
    (workshop_id, workshop_name, production_line, workshop_type, capacity_per_day)
SELECT workshop_id, workshop_name, production_line, workshop_type, capacity_per_day
FROM (
    SELECT workshop_id, workshop_name, production_line, workshop_type, capacity_per_day,
           ROW_NUMBER() OVER (PARTITION BY workshop_id ORDER BY update_time DESC, etl_time DESC) AS rn
    FROM ods_db.ods_mes_workshop
) t
WHERE rn = 1;
