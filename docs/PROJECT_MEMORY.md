# 项目记忆 / 交接说明（PROJECT_MEMORY.md）

> **这个文件是干什么的**：把"不在代码里"的项目知识——口径决策、踩过的坑、运维约束、未完成事项——
> 写成仓库内的文件，让接手的人打开 `D:\data_warehouse_project` 就能上手，不依赖任何工具的私有记忆。
>
> - 依据来源：git 历史、`README.md`、`FineBI看板搭建步骤.md`，以及 ETL 脚本原文核对
> - 历史沿革：原 `BI看板数据修正说明.md`（四轮追加式记录，含大量过期数字）已**合并进
>   `FineBI看板搭建步骤.md`** 并删除；口径速查见其**附录 B**，本文档保留口径决策与故障复盘的完整版
>
> **建议阅读顺序**：`README.md`（怎么跑）→ 本文件（为什么这么做 / 有什么坑）→ `FineBI看板搭建步骤.md`（看板怎么搭）

---

## 0. 30 秒上手

- **一句话**：基于 **MySQL 8 + Python + FineBI 6** 的制造业经营分析数仓 Demo，实现「业务源库 → ODS → DWD → DWS → ADS → 7 张 FineBI 看板」完整链路，数据全部由 Python 仿真生成。
- **现在能跑**：生成器、ETL（跑前自检 + 跑后 19 项校验）、离线图表渲染、Jupyter 分析。
- **当前数据范围**：`2025-10-01 ~ 2026-09-18`（353 天逐日无断层）。
- **库连接**：`root / root @ localhost:3306`，可用 `DB_HOST / DB_PORT / DB_USER / DB_PASSWORD` 覆盖。
- **FineBI**：`http://localhost:37799`，分析主题「制造数仓看板」连 `ads_db`，**抽取模式**（改数要手动「更新」）。

---

## 1. 架构（五层链路）

```
erp_db / mes_db / wms_db（源库 11 张）
   │ step01 全量 + 增量同步（水位表 etl_watermark）
ods_db（11 张）       贴源
   │ step02 清洗 / step03 维度 + 事实
dwd_db（7 维度 + 6 事实）
   │ step04 日 / 月聚合
dws_db（5 张）
   │ step05 指标计算
ads_db（6 张宽表）→ FineBI 7 个看板
```

建表：`sql/01_source_ddl` ~ `sql/05_ads_db` 分层 DDL（**唯一数据源**），
由 `scripts/build_init_sql.py` 汇总生成 `sql/00_init_all.sql`（7 库 + 46 张表，**生成物，勿手改**）。

ETL 脚本：`sql/06_etl_scripts/step00 ~ step05`。

---

## 2. 日常运行

```powershell
cd D:\data_warehouse_project

# 每天：补增量（默认只生成"今天"；已有数据的日期自动跳过）
python scripts\generate_incremental_data.py
python scripts\generate_incremental_data.py 2026-07-01 2026-09-10   # 回补区间缺口

# 跑 ETL（约 20~30 分钟；跑前自检建表脚本，跑后跑 19 项数据校验）
python scripts\etl_scheduler.py --once
# 常驻调度：先跑一次，之后每天 02:00 跑
python scripts\etl_scheduler.py

# 只用校验 / 只用渲染图
python scripts\verify_data.py
python scripts\render_quadrant_chart.py

# FineBI：数据 → 分析主题 → 更新 → 浏览器 Ctrl+F5
```

### ⚠️ 全量重建源数据的**铁顺序**（漏一步 ODS 就会翻倍）

```
generate_fake_data.py  →  sql/06_etl_scripts/step00_ods_full_reset.sql  →  etl_scheduler.py --once
```

1. `python scripts\generate_fake_data.py`（默认 **TRUNCATE 源库 11 张表**，约 40~90 分钟；`--append` 可不清表）
2. 用 MySQL 客户端执行 `sql/06_etl_scripts/step00_ods_full_reset.sql`（清空 ODS + 重置增量水位）
3. `python scripts\etl_scheduler.py --once`

原因：`step01` 是**追加式增量同步**（水位 + UPSERT）。源库被全量重建后主键全新、`update_time` 全是当天，
水位会把整批数据当成"新增"追加进 ODS → ODS 翻倍 → DWD 重建量翻倍 → 磁盘被打爆（第三轮故障的直接诱因，见 §5.1）。
**`step00_ods_full_reset.sql` 不要放进每日调度链。**

另外：**只跑生成器不跑 ETL，看板不会变。** 第 1 步会清空源表，执行前确认没有其他程序在读这三个库。

---

## 3. 关键口径决策

| # | 决策 | 理由 / 背景 | 落点 |
|---|---|---|---|
| 1 | **订单履约率改口径为「交付及时率」** = 按时交付订单数 ÷ **已交付**订单数 | 原口径分母含 17 万条**未发货**订单（`delivery_date IS NULL`），把指标压到 20.77%；改为只看已交付后升到 26.73%（旧数据），新生成器按时率 88% | `dws_sale_day.delivery_cnt`、`step04`、`step05` |
| 2 | **营收剔除「已取消」「已作废」订单** | 原实现把已取消订单计入营收，**虚高约 20%** | `step04` / `step05`：`WHERE order_status NOT IN ('已取消','已作废')` |
| 3 | **「营收缺口」预警口径 = 已取消订单金额占当月下单金额 ≥ 12%** | 原口径（产品营收环比下滑 ≥20%）在现有数据下**恒为空**（实测产品/客户/区域三个层面环比下滑数都是 0）；基础取消率约 10%，阈值从 15% 下调到 12% 以避免空预警 | `step05` 第 315 行附近 |
| 4 | **「回款滞后」预警基准日 = 数据内最新发货日**，不用 `CURDATE()` | 否则同样数据不同天跑出不同结果，**不幂等** | `step05` 第 363 行附近 |
| 5 | **成本 = 单位成本 × 工单实际产量 × (1±4%)**，按 **物料 60% / 人工 22% / 制造费用 18%** 拆分 | 原来是 `uniform(100,5000)` 随机数，与产量脱钩 → 成本与产量对不上 | `generate_fake_data.py` |
| 6 | **价格 / 成本按产品 ID 确定性生成**（同产品每次运行结果一致） | 可复现；单位成本 80~600、标准售价 = 成本 ÷ (1−目标毛利率)、目标毛利率 22%~34% | `generate_fake_data.py` |
| 7 | **产量 : 销量 ≈ 1.09 倍** | 原来是 **9.2 倍**，导致"总成本 > 总营收"、看板之间互相打脸（曾用写死的 23.08% 毛利率掩盖） | `generate_fake_data.py`（工单计划产量区间收窄为 20~200） |
| 8 | **库存快照：结存 = 期初 + 累计入库 − 累计出库**，出库不超结存（库存永不为负） | 原来每天独立 `random(0,2000)`，与出入库无关 → 库存看板全是 0 | `generate_fake_data.py`、`dwd_stock_snapshot`；600 行/天（200 物料 × 3 仓库） |
| 9 | **`oee_rate` 列名保留，但实际口径是「产能达成率 = 实际产量 / 计划产量」** | 名不符实是历史遗留；**改列名会打断已做的 FineBI 图表绑定**，所以只加注释不改名 | `step04` 第 45 行有明确注释 |
| 10 | **缺数据宁可留 NULL，不填估算值** | 成本凭证停在 2026-06 → 7 月后成本/利润指标为空，属**有意为之**，不要"修"成 0 或估算值 | `step05` |
| 11 | **`dim_date` 按 ODS 实际日期动态重建** | 原来是写死日期且无人使用；现已接入大屏日期脊柱 | `step02` / `step05` |
| 12 | **「已退货」状态补齐** → `return_amt` 不再恒为 0 | 现约 5.6 亿元 | `generate_fake_data.py` |

---

## 4. 工程约定（改代码前必读）

1. **`sql/01~05` 是建表脚本的唯一数据源**。改了分层 DDL 后必须跑 `python scripts\build_init_sql.py` 重新生成 `sql/00_init_all.sql`；
   忘了的话下次 ETL 日志会提醒（`--check` 可单独校验）。
2. **四道自动检查**（都挂在 `etl_scheduler.py`，性质不同）：
   - 跑前 `maintain_partitions.maintain()`：补齐 DWD 事实表的**未来月份分区** → **失败不阻断**（分区不全会落到 pmax，功能仍正确）
   - 跑前 `check_disk_space()`：MySQL `datadir` 所在盘剩余空间 → **不足则直接中止**（防爆盘）
   - 跑前 `build_init_sql.check()`：`00_init_all.sql` 是否与分层 DDL 同步 → **只警告，不阻断**
   - 跑后 `verify_data.run()`：19 项数据断言 → **失败即整批算失败**（数据不自洽是真问题）
   - 跳过开关：`--skip-partition-maintain` / `--skip-disk-check` / `--min-free-gb` / `--skip-init-check` / `--skip-verify`
3. **`verify_data.py` 的 19 项断言分三组**：规模（ADS 表非空 + 打印真实行数/日期范围）、
   对账（营收/产量跨层一致 DWD = DWS = ADS，容差 0.1% 相对误差，容忍 `ROUND` 舍入漂移）、
   一致性（预警 5 类齐全且主键唯一、库存健康单一基准日、大屏逐日无断层、维度无孤儿——
   注意 `UNKNOWN` 之类上游占位值**不算孤儿**，已列入白名单）。
4. **`etl_scheduler.py: COMMIT_PER_STATEMENT = True`**：每条 SQL 单独提交。这是第三轮"disk full"事故的对策，
   **不要贸然改回整脚本单事务**（峰值 undo/binlog 会撑爆磁盘）。
5. **`TRUNCATE` 隐式提交的原子性缺口 —— 目前存在于 step03 / step04 / step05**：
   调度器是"整个脚本成功才 commit"，而这 3 步的清理动作都是 **DDL（隐式提交、不可回滚）**：
   - step03：`ALTER TABLE ... TRUNCATE PARTITION`（按分区增量）
   - step04 / step05：`TRUNCATE TABLE`（DWS/ADS 全量重建）
   → 若清理之后的 `INSERT` 失败，会留下**已清空的分区/表**。
   
   **缓解**：这 3 步都**幂等**，重跑即恢复。且 step04/05 的源（DWD）完好，可从 DWD 重算。
   **彻底解决**要改成 `EXCHANGE PARTITION`（把算好的临时表原子换入分区）—— 见 §7。
   > 历史沿革：曾短暂改成 `DELETE ... WHERE <日期> BETWEEN`（DML、可回滚），但实测
   > **DELETE 43 万行要 151 秒**（比 INSERT 本身还贵），于是改回 `TRUNCATE PARTITION`（秒级）。
   > 这是"原子性 vs 性能"的显式取舍，不是疏忽。
6. **matplotlib 不要用 U+2212「−」（真减号）**：notebook 字体是 `SimHei`（GB2312 系），没有该字形，图上会显示成方框 `□`，用 ASCII `-`。
   `scripts/render_quadrant_chart.py` **刻意**与 notebook 使用完全相同的字体配置，就是为了让离线预览暴露这类字体问题——**别把它换成字形更全的字体**。
7. **Jupyter 改完代码要 Restart & Run All**：历史上两次出现"新图被 Jupyter 内存里的旧代码覆盖"，
   白跑一趟并污染了 commit。
8. **所有脚本/Notebook 的数据库连接一律读 `DB_HOST / DB_PORT / DB_USER / DB_PASSWORD`**，不要写死密码
   （旧增量脚本里的 `'你的密码'` 占位符已修）。
9. **看板铁律：表粒度决定聚合方式**（见下）。这是第一轮"翻车"的根因。

   | 表 | 每行代表 | KPI 卡正确做法 |
   |---|---|---|
   | `ads_boss_dashboard` | **一天**的经营全貌（353 行逐日快照） | ⚠️ 必须筛选到某一天，**不能直接求和** |
   | `ads_sale_analysis` | 一天 × 一客户 × 一产品 | ✅ 求和 |
   | `ads_produce_monitor` | 一天 × 一车间 × 一产品 | ✅ 数量求和；**比率要重算** |
   | `ads_stock_health` | 一物料 × 一仓库（**单日快照**） | ✅ 求和 |
   | `ads_cost_profit` | 一月 × 一产品 × 一车间 | ✅ 成本额求和；比率用平均值 |
   | `ads_alert_warning` | **一条预警** | ✅ COUNT |

   比率型字段（%、天数）用计算字段重算，不要"求和"也不要直接"平均值"：
   `产能达成率 = SUM(actual_qty)/SUM(plan_qty)`、`良品率 = SUM(qualified_qty)/SUM(actual_qty)`、
   `交付及时率 = SUM(delivery_ontime_cnt)/SUM(delivery_cnt)`；分母一律 `NULLIF(...,0)` 保护。
   > ⚠️ **交付及时率的分母是「已交付订单数」而不是「订单数」**。写成
   > `SUM(order_cnt × delivery_ontime_rate)/SUM(order_cnt)` 会偏低约 7.5 个点
   > （实测：2026-09-18 正确 87.84% vs 错误写法 80.41%）。
   > 且 `ads_sale_analysis` 只有比率列、无计数列，**在该表上无法正确加权** —— 需用 `dws_sale_day`。

10. **`generate_fake_data.py` 的 `END_DATE` 是不含端点的**：`END_DATE = 2026-06-30`，
    实际生成到 **2026-06-29** 为止；而增量脚本的区间从 2026-07-01 起 ——
    所以 **2026-06-30 这一天历史上一直是空的**，谁都不会去补它，
    却会让 `verify_data.py` 的「大屏逐日无断层」断言失败（行数 342 ≠ 跨度 343 天）。
    已于 2026-09-18 用 `generate_incremental_data.py 2026-06-30 2026-06-30` 补齐。
    **改动 `START_DATE` / `END_DATE` 时，请把"端点是否含入"写清楚，或改成 `END_DATE + 1 天` 循环。**

11. **`stock_io_detail` 没有业务唯一键**（主键只是 UUID `io_id`），
    同样的重复写入不会报错，只会静默翻倍。判断某天"是否已生成"必须以
    **每张被写的表自己的业务日期列**为准，不能拿 `erp_db.sale_order` 代表整天（见 §5.6）。

12. **DWD 事实表按业务日期做月度 RANGE 分区**（`dwd_db` 的 6 张 `dwd_*`）。
    改这些表时注意三条：
    - **分区列必须出现在每个唯一索引（含主键）里** —— 这是 MySQL 的硬性要求。
      所以 5 张表的 PK 是复合键：`dwd_sale_order_detail(order_id, order_date)`、
      `dwd_produce_workorder_detail(workorder_id, plan_start_date)`、`dwd_stock_io_detail(io_id, io_date)`、
      `dwd_cost_detail(voucher_id, cost_month)`、`dwd_equipment_runtime(record_id, record_date)`。
      ⚠️ **不要再按 id 单独做 `ON DUPLICATE KEY UPDATE`** —— 复合键下不会再冲突。
    - **分区维护**：`scripts/maintain_partitions.py`（跑批前自动调用）补齐"当前月 ~ 未来 3 个月"。
      末尾是 `pmax (MAXVALUE)`，所以**不能直接 `ADD PARTITION`**，必须
      `REORGANIZE PARTITION pmax INTO (新分区..., pmax)`。
    - 分区列是 `'YYYY-MM'` 字符串的表只有 `dwd_cost_detail`（`cost_month`），
      字典序恰好等于时间序，可以直接当 `RANGE COLUMNS` 边界。

13. **step03 是「按分区增量」**：**按整月分区重算**，不用逐行 DELETE。
    重算范围 = `[ODS 最大业务日期所在月的前一个月, ODS 最大业务日期所在月]`（2 个整月）。
    清理用 `ALTER TABLE ... TRUNCATE PARTITION pA, pB`（**秒级**），再 `INSERT ... SELECT` 该区间。
    DWD 为空（首次 / 整表重建）时自动切换为 `TRUNCATE TABLE` + 全量（用 `@dwd_max IS NULL` 判断）。

    > **为什么不用 DELETE**：实测过 DELETE 版，增量 295.7 秒，其中 `DELETE 43 万行 ≈ 151 秒`
    > （逐行标记删除 + 维护 13 棵分区索引 + undo/binlog），**比 INSERT 本身还贵**。
    > 改成 `TRUNCATE PARTITION` 后增量 **101.4 秒（提速 2.9 倍，相对改造前全量 3.5 倍）**，6 张表行数零变化。

    ⚠️ **注意两点**：
    - `TRUNCATE PARTITION` 会清空**整个分区**，随后 INSERT 必须完整回填那 2 个月，否则丢数据
    - 它是 DDL、隐式提交 → 见第 5 条的原子性说明（幂等，重跑可恢复）
    - **历史缺口**：该设计只重算最近 2 个月，更早的历史缺口不会被自动补；需要补就手工清表重跑（会退化为全量）

14. **维度 SCD Type 2 —— 规划中，尚未实施**（设计已定，见 §7）：
    前提已就绪：`generate_incremental_data.py` 的 `generate_incremental_dimension()`
    每次运行变更约 1% 的维度属性（**只改 `customer.grade` 与 `product.category_l2`**，
    **绝不能改 `product.standard_cost`** —— 被成本/毛利指标引用）。
    但 `dim_customer` / `dim_product` 的**建表 DDL 与 step02 加载逻辑还没改**，所以目前
    维度仍是"每日全量重建、只留当前版本"，不会产生历史。
    > ⚠️ **实施时三件事必须一起改，否则必崩**（详见 §7）：
    >   · dim DDL 加 `valid_from/valid_to/is_current/version`，主键改 `(业务主键, valid_from)`；
    >     用「生成列 `cur_key` + 唯一键」保证每个主键最多一条 `is_current=1`
    >   · step02 改成 SCD2 合并（关旧版本 → 插新版本）
    >   · **step05 里所有 JOIN 这两张维度的 6 处都要加 `AND x.is_current = 1`** ——
    >     漏一处就是一个主键匹配多行 → **笛卡尔积**（营收/产量翻倍）

---

## 5. 踩过的坑 / 故障复盘

### 5.1 第三轮：ETL 报 `The table 'dwd_stock_io_detail' is full`

**双重根因**：
1. **C 盘被写满**：MySQL data 目录在 `C:\ProgramData\MySQL\...`，C 盘 200 GB 当时只剩 12.85 GB；
   `log_bin = ON` 且 `binlog_expire_logs_seconds = 2592000`（30 天）→ binlog 堆到 **7,434 MB**（其中两个文件 1,120 MB / 971 MB）；
   而 `step03` 原本把**几百万行 INSERT 放在一个事务**里，提交时一次性写出巨大 binlog 事件 + 巨大 undo，直接把盘顶爆。
2. **ODS 翻倍**：源库被全量重建后 `step01` 把它当增量追加（订单 100 万→200 万、工单 50 万→100 万…），写入量翻倍。

**已处置**：清空 ODS 11 张表 + `etl_watermark`；`PURGE BINARY LOGS BEFORE NOW()`（binlog 7,434 MB → 971 MB，C 盘 15.67 GB → 21.98 GB）；
`SET GLOBAL binlog_expire_logs_seconds = 86400`（**重启后失效，需写进 `my.ini`**）；
新增 `step00_ods_full_reset.sql`；`etl_scheduler.py` 加 `COMMIT_PER_STATEMENT = True`。

**副产品**：该次失败后 DWD 曾全空（TRUNCATE 隐式提交 + INSERT 回滚），表空间文件未释放，重跑 TRUNCATE 时会自动回收。

### 5.2 第一轮：库存看板整块是空的（最严重）

根因是**项目缺 `dwd_stock_snapshot` 这张 DWD 事实表**，库存链路断在 DWD 层。补表 + `step03` 增加入仓后修复。

### 5.3 第一轮：`step04` / `step05` 里 6 处硬编码"假指标"、时间范围写死、大屏只有 1 行

全部去硬编码：毛利率等改为真实计算、时间范围动态、大屏改逐日快照（1 行 → 272 行）。
**6 张 ADS 表的字段名/字段数一张都没变**，所以 FineBI 里已做的图表绑定不用重做——这是刻意保持的兼容性，改动时请继续遵守。

### 5.4 FineBI 刷新后数据没变

不是数据没进，是**分析主题用「抽取数据」而不是直连**：需要「数据 → 该分析主题 → 更新」，再 `Ctrl+F5`。
另有一个高频误判：`ads_boss_dashboard` 是逐日快照，KPI 卡若用「求和」会显示 273 天累计值（"当日总营收"变成 13.55 亿），
正确做法是绑定 `stat_date = 最新日期` 或加日期筛选器。

### 5.5 其他已修的历史问题（在生成器/增量脚本里）

N+1 查询（50 万次单行 `SELECT` → 一次 load 成字典，这是整脚本曾跑 8 小时的主因）、
成本月份随机、良品 + 不良 ≠ 实际产量、设备四项时间之和 ≠ 1440（OEE 算不出）、
重复运行成倍累加（旧脚本不清表，库里 100 万订单其实多次累加的结果）、
增量日均量级写死 50 单/天（历史日均 3,663 单，日均营收只有历史的 1/70，已改为从历史自动推算）。

---

### 5.6 第五轮：增量回补把 7 月出入库写了两遍

**现象**：执行 `python scripts\generate_incremental_data.py 2026-07-01 <今天>` 回补缺口时，
2026-07-03 起每天报

```
(1062, "Duplicate entry '019488e3...-原材料仓-2026-07-03' for key
 'stock_snapshot.uk_material_warehouse_date'")
```

但同一天的销售订单 / 生产工单 / 成本凭证都提示"✅ 完成"。

**根因（三处叠加）**：

1. **判据用错了表**。旧的 `date_has_data()` 只看 `erp_db.sale_order`，
   而源库各表的日期覆盖**本来就不一致**：全量生成时库存快照/出入库被多铺了一个月
   （`SNAPSHOT_END = 2026-07-31`），销售订单只到 2026-06-30
   （`END_DATE = 2026-06-30`）。于是 7 月被判定为"没有数据"→ 重复生成。
2. **`stock_snapshot` 有唯一键，`stock_io_detail` 没有**。
   重复生成时快照必然撞 `uk_material_warehouse_date` 报 1062；
   而流水表主键只是 UUID `io_id`，**没有任何业务唯一约束**，
   于是同一天被静默写了两遍（约 1500 行 → 约 3000 行），出入库统计直接翻倍。
3. **`batch_insert()` 内部逐批 `commit()`**，外层的 `conn.rollback()` 形同虚设 ——
   失败时只能回滚最后一批，流水已经落库。这是**与 §4.5 `TRUNCATE` 同源的一类问题**：
   提交粒度比业务步骤细，失败就没有原子性可言。

**连带影响**：`generate_incremental_stock` 抛异常后，同一 `try` 块里的
`generate_incremental_equipment` 永远不会执行 → 7 月设备运行记录整体缺失
（`equipment_runtime` 停在 2026-06-30；但该表不参与 DWS/ADS，看板无影响）。

**修复**（`scripts/generate_incremental_data.py`）：

- **逐表幂等**：新增 `table_date_count()` + `DATE_GUARDS` + `day_is_complete()`，
  每张源表按**自己的业务日期列**判断是否已有数据，缺哪张补哪张（不再只看销售订单）。
- **库存步骤特判**：快照已存在 → 整步跳过（保住历史快照）；流水已在但缺快照 → 只补快照，
  按已有流水的净变化推导结存；两者都缺 → 正常生成。
- **成本凭证按"当日工单是否都已挂凭证"判断**（原本只有 `cost_month`，按月判断会漏掉月中回补）。
- **单步隔离**：5 个步骤各自 `try/except`，某步失败不再连累后面的步骤。
- **提交粒度对齐步骤**：`batch_insert()` 去掉内部 `commit()`，改由每个生成函数在整批成功后提交。

**善后工具**：`scripts/repair_stock_io_dupes.py`（默认 dry-run，`--apply` 才删；
先备份到 `wms_db.stock_io_dupe_bak_<日期>`，并保证不会把某一天删空；
会同时清理 `ods_db.ods_wms_stock_io`，因为源库删行不会传播到 ODS）。
本次清理：2026-07-01 ~ 2026-07-31 共 **45,971 行**重复流水，已备份到
`wms_db.stock_io_dupe_bak_20260918`（确认无误后可删该备份表）。
ODS 当时还没跑过 ETL，故 ODS 侧删除 0 行。

> **教训**：做"按天回补"时，**幂等判据必须覆盖被写的每一张表**，
> 而不能用其中一张表代表整天的完成状态。各表日期覆盖范围不一致是常态，不是例外。



## 6. 数据现状（用前请复核）

> 2026-09-18 完成了源数据回补（06-30 补缺、7~9 月增量、清理 7 月重复流水）并全量重跑 ETL，
> **19 项断言全部通过，退出码 0**。上一轮（2026-09-16）数字见本节末尾对照。

| 表 | 行数 | 日期范围 |
|---|---|---|
| `ads_boss_dashboard` | 353 | 2025-10-01 ~ **2026-09-18**（逐日，无断层） |
| `ads_sale_analysis` | 1,105,983 | 2025-10-01 ~ 2026-09-18 |
| `ads_produce_monitor` | 331,853 | 2025-10-01 ~ 2026-09-18 |
| `ads_stock_health` | 600 | **2026-09-18**（基准日已前移到位） |
| `ads_cost_profit` | 14,454 | 2025-10 ~ 2026-09（12 个月） |
| `ads_alert_warning` | 78 | 五类预警（⚠️ 见 §7.0「回款滞后」基准日跑到未来） |
| `dwd_db.dim_date` | 383 | 2025-09-01 ~ 2026-09-18 |

全量口径：营收 **260.33 亿**（DWD = DWS = ADS 四层一致）；
生产 plan/actual/defect = **71,105,047 / 55,384,455 / 4,795,173**（不良率 8.66%）。
源库数据量：`erp_db.sale_order` **1,297,751** 行、`mes_db.produce_workorder` **648,878** 行；7 库合计约 **5.3 GB**。

重跑耗时参考（2026-09-18，数据量比上轮大 ~30%）：step01 97s、step02 28s、step03 **355s**、
step04 **463s**、step05 **652s**，**合计 1,595s ≈ 26.6 分钟**。

<details>
<summary>上一轮（2026-09-16）对照数字</summary>

| 表 | 行数 | 日期范围 |
|---|---|---|
| `ads_boss_dashboard` | 272 | 2025-10-01 ~ 2026-06-29 |
| `ads_sale_analysis` | 852,421 | 2025-10-01 ~ 2026-06-29 |
| `ads_produce_monitor` | 255,943 | 2025-10-01 ~ 2026-06-29 |
| `ads_stock_health` | 600 | 2026-07-31（基准日；看板基准日取 2026-06-29） |
| `ads_cost_profit` | 10,854 | 2025-10 ~ 2026-06（9 个月） |
| `ads_alert_warning` | 61 | 五类预警 |

营收 208.08 亿；plan/actual/defect = 54,759,726 / 42,384,170 / 3,742,776；step03~05 合计约 15 分钟。
</details>

**复核方式**（权威来源永远是库，不是文档）：

```powershell
python scripts\verify_data.py     # 19 项断言，全通过退出码 0；会打印真实行数 / 日期范围
```

> ✅ **文档数字不一致问题已清理**：原先两处数字打架（库存金额 `4,709.6 万元` vs
> `92,755.3 万元`、大屏行数 `272/273` vs `353`）来自不同轮次的中间态残留。
> 现已把 `BI看板数据修正说明.md` 合并进 `FineBI看板搭建步骤.md` 并删除，
> 该手册内的"对答案"数字全部换成 **2026-09-18 实测值**。
> **引用任何数据前，先跑一次 `verify_data.py`** —— 库才是权威来源。

---

## 7. 未完成事项 / 待决策（**接手后优先看这里**）

> 本节只列**还没做**的；已完成/已解决的压缩在文末「已闭环留档」。

1. **「回款滞后」预警的基准日跑到了未来（待决策）**：
   `step05` 第 11.5 段用 `SET @as_of_date = (SELECT MAX(delivery_date) FROM dwd_db.dwd_sale_order_detail)`
   —— 初衷是为了幂等（不用 `CURDATE()`，见 §3 第 4 条），本身没错。
   但增量生成器给出的 `delivery_date` 是 `order_date + 1~40 天`，最近订单的发货日
   最远推到未来，而 DWD 里 `delivery_date > CURDATE()` 的订单有 **18,617 笔**。
   结果：`ads_alert_warning` 中「回款滞后」30 条的 `alert_date` 全部是未来日期，
   看板「异常预警清单」上会出现未来日期。
   **两种修法（择一，属口径变更，按 §9 先改本文件再改 SQL）**：
   - **口径侧（推荐，不动数据）**：`@as_of_date` 改用"数据内最新**业务日**" ——
     即 `MAX(order_date)` 或 `LEAST(MAX(delivery_date), MAX(order_date))`，
     既保持幂等，又不会越过数据截止日。
   - **数据侧（治本但需重建）**：生成器限制"只有已发货/已完成状态才给 `delivery_date`，且不超过生成时刻"。
     这会改变历史分布，需全量重建源数据（走 §2 的铁顺序）。

2. **`TRUNCATE` 的原子性**：建议改成"写入临时表 → 成功后再原子切换"，或把 TRUNCATE 挪到 INSERT 之后（§4.5）。

3. **MySQL 运维项**：
   - ⬜ **把 `datadir` 从 C 盘迁到 D 盘**（C 约剩 24 GB / D 约剩 227 GB）。
     **紧迫性已下降**：binlog 已收敛到 1 天保留，且跑批前有自动磁盘检查兜底（见文末已闭环），
     所以这项可以等到有维护窗口时再做。
     > ⚠️ `my.ini`（`C:\ProgramData\MySQL\MySQL Server 8.0\my.ini`）**当前用户不可写**，
     > 必须用**管理员 PowerShell**；这是**不可逆操作**，请严格按下面顺序，出问题按最后一步回滚。
     ```powershell
     # 1) 复核现值：my.ini 中 datadir=C:/ProgramData/MySQL/MySQL Server 8.0\Data
     # 2) 确认服务名（services.msc 里看，常见 MySQL80）
     # 3) 停服务
     net stop MySQL80
     # 4) 复制数据（/COPYALL 保留 ACL，/DCOPY:T 保留目录时间戳）
     robocopy "C:\ProgramData\MySQL\MySQL Server 8.0\Data" "D:\MySQL\Data" /E /COPYALL /DCOPY:T /R:1 /W:1
     # 5) 校验复制结果（只列表不复制，核对文件数/大小是否一致）
     robocopy "C:\ProgramData\MySQL\MySQL Server 8.0\Data" "D:\MySQL\Data" /L /E /NJH /NDL /FP /NS /NC
     # 6) 编辑 my.ini：datadir 改为 D:/MySQL/Data    （改前先备份 my.ini）
     # 7) 起服务
     net start MySQL80
     # 8) 验证（应全部通过）
     mysql -uroot -p -e "SELECT @@datadir; SHOW BINARY LOGS;"
     python scripts\verify_data.py
     ```
     **回滚**：把 `my.ini` 的 `datadir` 改回原路径 → `net stop` / `net start`。
     **确认一切正常之前，不要删 C 盘的旧 `Data` 目录**（它是唯一的回滚路径）。
   - ⬜ 本项目无主从复制，可选 `skip-log-bin` 直接关掉 binlog
   - ⬜ 数据量太大可把 `SALE_ORDER_COUNT` 从 100 万降到 30 万（全库体积约 1/3）

4. **被 `.gitignore` 排除、换机器需要手动搬的产物**：`bl/*.pdf`（7 份看板导出 PDF，约 5.9 MB）、
   `logs/`（ETL 日志）、`.vscode/`、`_bi_review/`（BI 复核临时产物，当前已清理）。**同机换工具不受影响**。

5. **FineBI 四象限图的两个小问题（已决定暂不改动）**：Y 轴标题仍是默认的「组件」；
   轴范围过宽导致左侧上方大片空白。改法见 `FineBI看板搭建步骤.md` §3.4。

### 已闭环留档（已完成，不再跟踪）

- ✅ **增量脚本缺口 + 历史空档**：补齐了 2026-07~09、`2026-06-30`（生成器 `END_DATE` 不含端点，见 §4.10）
  和 `2026-08-25/08-26`（旧版无单步隔离，库存步骤失败连累了设备运行）。
  现状 5 张源表 2026-06-30 ~ 2026-09-18 **各 81 天无缺口**。回补重复写入的坑见 §5.6，
  清理工具 `scripts/repair_stock_io_dupes.py`。
- ✅ **远程仓库已建并推送**：`github.com/q2898322792/manufacturing-dw`。
  推送前做了 `.git` 清理：曾 **57 MB**（而工作区被跟踪文件仅 1.3 MB），差额是
  **6 个 2.7~11.5 MB 的超大 PNG 截图**（`12429×6045` 量级，早期 BI 复核产物）
  **+ 52 个 unreachable blob**；经 `git rev-list --objects --all` 核对全是游离对象 →
  `git gc --prune=now` 清除 → **2.8 MB**。
  > 教训：**别把整页大截图 `git add` 进仓库**；`_bi_review/` 被忽略不是偶然。
- ✅ **文档轮次混乱**：`BI看板数据修正说明.md`（四轮追加式、行数全是中间态）与
  `FineBI看板重建步骤.md` 内容重叠 → 合并为一份 **`FineBI看板搭建步骤.md`**，
  所有"对答案"数字换成实测值，"历史故障复盘"只保留在本文件 §5。
- ✅ **交付物可见性**：7 张看板截图（统一 1434 px、共 1.35 MB）+ README 重写
  （规模速览 / 技术栈 / 指标口径 / 已知不足），首屏放「经营总览大屏」当门面。
  ⚠️ **图片加载链路**：GitHub 对**仓库内相对路径**渲染成 `github.com/.../raw/...`
  （302 → `raw.githubusercontent.com`），对**外部绝对 URL**（如 jsDelivr）则包进
  `camo.githubusercontent.com` —— **两个都是 GitHub 域名**，部分国内网络下不可达。
  现用 jsDelivr + camo，实测可正常显示。
- ✅ **MySQL binlog 保留期**：原为默认 **30 天**（`2592000`）且 my.ini 里没写这一项 →
  重启即回 30 天，曾堆积 **1.2 GB**。已用 **`SET PERSIST binlog_expire_logs_seconds = 86400`**
  持久化（写入 datadir 下的 `mysqld-auto.cnf`，可用 `performance_schema.persisted_variables` 验证，
  **重启依然生效**），并 `PURGE BINARY LOGS BEFORE NOW()` 清掉堆积 → C 盘 +1.1 GB。
  > 比改 `my.ini` 更好：**不需要管理员权限、不需要重启服务**。
- ✅ **跑批前磁盘空间检查**：已内置到 `scripts/etl_scheduler.py`（`check_disk_space`）——
  自动检查 MySQL `datadir` 所在盘，低于阈值（默认 **15 GB**）**直接中止跑批**
  （因为爆盘会重演 §5.1 的 `table is full` 事故）。可用 `--skip-disk-check` / `--min-free-gb` 覆盖。
- ✅ **FineBI 看板缺陷（已修 2 项）**：大屏「当日总利润」被卡片裁切（显示 `2,450,410.9`，
  真实 `12,450,410.91`）→ 数值格式单位改「万」；生产监控「当前产能达成率」口径错
  （`77.76` = 全量 353 天逐行平均）→ 改加权计算字段 + 日期过滤，现为 `79.26%`。
  逐步操作见 `FineBI看板搭建步骤.md` §四。
## 8. 交接备注（环境事实）

- **工作目录**：`D:\data_warehouse_project`（项目本体与工具无关，任何人打开该目录即可接手）。
- **环境近况**：MySQL data 目录在 C 盘（**C 盘空间是本项目最大的系统性风险**），FineBI 6.0 在 `localhost:37799`；
  项目里有 `cleanup-c-drive.ps1` 可用于清理 C 盘（清 MySQL binlog 等）。
- **数据是仿真数据**，不是真实业务数据；口径以本文件 §3 为准，业务口径变更请**先改本文件再改 SQL**。

---

## 9. 维护本文件的约定

- 口径、约定、踩坑、遗留项发生变化时**同步更新本文件**，不要只改代码或只改聊天记录。
- 数字类内容一律标注"实测日期"，避免过期数字被当成事实。
- 与本文件冲突时，优先级：**库内实测 > 代码注释 > 本文件 > 其它 md 文档**。
