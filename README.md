# 制造企业经营分析数据仓库

基于 **MySQL 8 + Python + FineBI 6** 的制造业经营分析数据仓库，完整实现
「业务源库 → ODS → DWD → DWS → ADS → 可视化」五层链路，配 **7 张 FineBI 看板**与
**19 项可执行的数据质量断言**。数据由 Python 仿真生成，全链路可独立复现。

| 规模速览（2026-09-18 实测） | |
|---|---|
| 数仓分层 | 7 个库 / **46 张表**（源 11 + ODS 11 + DWD 13 + DWS 5 + ADS 6） |
| 数据量 | 约 **5.3 GB**；源库销售订单 **129.8 万行**、生产工单 64.9 万行 |
| 数据范围 | `2025-10-01 ~ 2026-09-18`，**353 天逐日无断层** |
| 最大结果表 | `ads_sale_analysis` **110.6 万行** |
| ETL 全流程 | **26.6 分钟**（step01~step05，实测 1,595 秒） |
| 数据校验 | `verify_data.py` **19 项断言**，全通过退出码 0 |

![经营总览大屏](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/01-boss-dashboard.png)

---

## 项目亮点

1. **五层数仓全链路落地** —— 源库 → ODS（贴源 + 增量水位 `etl_watermark`）→ DWD（7 维度 + 6 事实）
   → DWS（日 / 月粒度）→ ADS（6 张看板宽表）。46 张表全部由分层 DDL 生成，
   `sql/01~05` 是唯一数据源，`00_init_all.sql` 由脚本汇总产出（不改手写）。

2. **19 项可执行的数据质量断言，且接入调度器** —— **校验不通过则整批算失败**。
   覆盖三类：规模（各表非空 + 真实行数/日期范围）、跨层对账（营收与产量 DWD = DWS = ADS，
   容差 0.1%）、一致性（预警 5 类齐全且主键唯一、大屏逐日无断层、维度无孤儿）。

3. **三处业务口径纠偏**（详见 [核心指标口径](#核心指标口径)）—— 营收剔除「已取消 / 已作废」订单；
   订单履约率分母由「全部订单」改为「**已交付订单**」；利润由营收 × 固定比例改为**毛利口径真实计算**。

4. **一次爆盘故障的完整根因复盘** —— `table is full` 由三重因素叠加：MySQL binlog 保留期过长、
   `step03` 把数百万行 INSERT 放在单个巨型事务、源库全量重建后 ODS 增量翻倍。
   处置包括 `PURGE BINARY LOGS`、逐条提交（`COMMIT_PER_STATEMENT = True`）、新增 ODS 全量重置开关。

5. **幂等性重构** —— 定位并修复「按天回补把同一天写了两遍」的问题（流水表无业务唯一键 → 静默翻倍）。
   根因是幂等判据只看单表；改为**逐表按各自业务日期判断 + 单步隔离 + 提交粒度对齐步骤**。

6. **事实表月度分区 + 按分区增量，实测提速 3.5 倍** —— DWD 的 6 张事实表按业务日期做
   **月度 `RANGE` 分区**（16 个月度分区 + `pmax`），跑批只重算「最近 2 个整月」：
   清理用 `TRUNCATE PARTITION`（元数据操作、秒级），再 `INSERT ... SELECT` 回填该区间。
   实测 `step03` **355 秒 → 101.4 秒**，6 张表行数零变化、19 项校验全过。
   > 中间踩过一次坑：先用 `DELETE ... WHERE <日期> BETWEEN` 做增量，实测 295.7 秒 ——
   > 拆解后发现 **DELETE 43 万行就要 151 秒**（比 INSERT 本身还贵），才换成 `TRUNCATE PARTITION`。
   > 已知取舍：它是 DDL、不可回滚，靠「幂等 + 重跑」兜底（详见 [已知不足](#已知不足与演进路线)）。

7. **跑批前后四道自动检查**（都挂在调度器上，可单独关掉）——
   分区维护（补齐未来月份）/ 磁盘剩余空间（不足则**中止**）/ 建表脚本同步（只警告）/
   跑后数据校验（失败则整批失败）。另补上了 ODS 缺失的日期索引，相关查询提速 12~41 倍。

---

## 架构

```
业务源库（erp_db / mes_db / wms_db，11 张表，全部为仿真数据）
        │  step01  增量同步（水位表 etl_watermark + UPSERT，幂等）
        ▼
ODS 层（ods_db，11 张）        贴源镜像，每行带 etl_time
        │  step02  维度重建（每日全量，取每个业务主键最新版本）
        │  step03  事实入仓（每日全量，含库存快照事实表）
        ▼
DWD 层（dwd_db，13 张 = 7 维度 + 6 事实）
        │  step04  汇总（日 / 月粒度）
        ▼
DWS 层（dws_db，5 张）         销售日/月、生产日、库存日、成本月
        │  step05  指标计算（6 张 ADS 宽表 + 五类预警）
        ▼
ADS 层（ads_db，6 张）         面向看板的指标宽表
        │  FineBI 抽取数据 → 更新
        ▼
7 张 FineBI 看板
```

| 层 | 库 | 表数 | 职责 |
|---|---|---|---|
| 源库 | `erp_db` / `mes_db` / `wms_db` | 11 | 业务仿真数据（ERP 5 + MES 3 + WMS 3） |
| ODS | `ods_db` | 11 | 贴源、增量同步（水位表 `etl_watermark`） |
| DWD | `dwd_db` | 13 | 清洗、去重、统一口径（7 维度 + 6 事实） |
| DWS | `dws_db` | 5 | 日 / 月粒度聚合 |
| ADS | `ads_db` | 6 | 面向看板的指标宽表 |

> 全链路实测耗时：step01 97s · step02 28s · step03 355s · step04 463s · step05 652s，合计 **26.6 分钟**。

---

## 技术栈

| 层级 | 组件 | 版本 | 说明 |
|---|---|---|---|
| 源数据库 | MySQL（3 个仿真源库） | 8.0.39 | 用 3 个独立库模拟 ERP / MES / WMS 异构源 |
| 数仓存储 | MySQL Community Server | 8.0.39 | 窗口函数 / CTE / `WITH RECURSIVE` |
| 数据生成与 ETL | Python + pymysql + Faker | Python 3.10 | 仿真数据生成、增量水位同步、逐条提交 |
| 数据加工 | 标准 SQL | — | 清洗、转换、聚合全在 SQL 中完成 |
| 任务调度 | Python `schedule` | 1.1+ | 每日 02:00 常驻调度；`--once` 单次模式便于排障 |
| 可视化 | FineBI（帆软） | 6.0 | 7 张看板，抽取模式 |
| 分析 | Jupyter Notebook | — | 客户 RFM 分层、车间「产能 × 良率」四象限 |

---

## 核心指标口径

指标口径全部体现在 ETL SQL 中，并由 19 项断言校验一致性。以下为关键项：

| 指标 | 口径 |
|---|---|
| 营业收入 | 有效订单含税总金额，**剔除「已取消」「已作废」订单** |
| **交付及时率**（订单履约率） | 按时交付订单数 ÷ **已交付订单数**（`delivery_date` 非空；未发货订单不计入分母） |
| 当日总利润 / 利润率 | **毛利口径** = 营收 − 当月已售产品成本（= 当月单位成本 × 销量）。源数据无期间费用，故不是净利润 |
| 产能达成率 | `SUM(实际产量) / SUM(计划产量)` —— 跨行聚合**必须加权**，不可对行级比率取平均 |
| 良品率 / 不良率 | `SUM(合格品) / SUM(实际产量)`、`SUM(不良品) / SUM(实际产量)` |
| 库存周转天数 | 当日库存金额 ÷ 近 30 天日均出库金额 |
| 呆滞物料 | 周转天数 > 90 天，或近 30 天无出库（`is_slow_moving = 1`） |
| 成本结构占比 | 物料 / 人工 / 制造费用 分别 ÷ 当月总成本 |

**关于「交付及时率」的口径纠偏**：原口径分母是「全部有效订单」，但库中有 17 万单**尚未发货**
（`delivery_date IS NULL`），被算作「不按时」，把指标压到 20.77%。改为只看已交付订单后，
指标回到业务可解释的区间（当前 **87.84%**）。

> 完整的 19 项指标口径（含数据来源、统计周期、维度约束）见
> [`制造企业经营分析数据仓库项目说明书.docx`](./制造企业经营分析数据仓库项目说明书.docx) 第 7 章。

---

## 环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| Python | 3.10+ | 脚本 + Notebook |
| MySQL | 8.0+ | 源库 + 五层数仓库（需支持窗口函数 / CTE） |
| FineBI | 6.0 | 看板（连 `ads_db`） |
| Python 依赖 | 见 `requirements.txt` | `pip install -r requirements.txt` |

数据库连接默认 `root / root @ localhost:3306`，可用环境变量覆盖：
`DB_HOST`、`DB_PORT`、`DB_USER`、`DB_PASSWORD`（所有脚本均不写死口令）。

---

## 快速开始

```powershell
# 1) 安装依赖
pip install -r requirements.txt

# 2) 首次初始化：建 7 个库 + 46 张表（幂等，可重复执行）
mysql -uroot -p < sql\00_init_all.sql

# 3) 全量生成仿真源数据（默认先 TRUNCATE 源库 11 张表，约 40~90 分钟）
python scripts\generate_fake_data.py

# 4) 【源库全量重建后必须执行一次】清空 ODS + 重置增量水位
#    漏掉这一步，step01 会把新数据当增量追加，ODS 直接翻倍
mysql -uroot -p < sql\06_etl_scripts\step00_ods_full_reset.sql

# 5) 跑 ETL 全流程（step01~step05，实测约 26.6 分钟）
#    跑前自动自检建表脚本，跑后自动执行 19 项数据校验
python scripts\etl_scheduler.py --once

# 6) 之后每天补增量（默认只生成「今天」）
python scripts\generate_incremental_data.py
#    或回补区间（已有数据的日期会自动跳过，可重复执行）
python scripts\generate_incremental_data.py <起始日期> <结束日期>

# 7) FineBI：数据 → 分析主题 → 更新 → 浏览器 Ctrl+F5
```

> **三个必须知道的点**：
> 1. **只跑生成器不跑 ETL，看板不会变。**
> 2. 重新生成源数据的**铁顺序**：`generate_fake_data.py` → `step00_ods_full_reset.sql` → `etl_scheduler.py --once`。
>    缺了 step00，ODS 会翻倍，磁盘可能被写满（历史上出过一次 `table is full`）。
> 3. 第 3 步会清空源表，执行前请确认没有其他程序在读这三个库。

---

## 目录结构

```
data_warehouse_project/
├── sql/
│   ├── 00_init_all.sql      # 一键初始化：7 库 + 46 张表（生成物，勿手改）
│   ├── 01_source_ddl/       # 源库建表（erp_db / mes_db / wms_db，11 张）
│   ├── 02_ods_db/           # ODS 贴源层（11 张）
│   ├── 03_dwd_db/           # DWD 明细层（7 维度 + 6 事实）
│   ├── 04_dws_db/           # DWS 汇总层（5 张）
│   ├── 05_ads_db/           # ADS 应用层（6 张）
│   ├── 06_etl_scripts/      # ETL 脚本（step00 ~ step05）
│   └── 数据查询/            # 手工查询 / 脏数据探查
├── scripts/                 # 数据生成、ETL 调度、校验、工具（Python，8 个）
├── notebooks/               # Jupyter 分析（RFM、产能质量四象限）+ 输出图
├── docs/
│   ├── PROJECT_MEMORY.md            # 项目记忆：口径决策、工程约定、故障复盘、未完成事项
│   └── screenshots/                 # 7 张看板截图（README 引用）
├── bl/                      # FineBI 看板导出的 PDF（已被 .gitignore 排除）
├── logs/                    # ETL 运行日志（已被 .gitignore 排除）
├── cleanup-c-drive.ps1      # 磁盘清理（清 MySQL binlog，防爆盘）
├── requirements.txt
└── 制造企业经营分析数据仓库项目说明书.docx    # 完整设计说明书（7 章）
```

---

## 看板（FineBI）

| # | 看板 | 数据源 | 说明 |
|---|---|---|---|
| 1 | 经营总览大屏 | `ads_boss_dashboard` | 逐日快照（353 行），**必须加日期筛选器** |
| 2 | 销售分析 | `ads_sale_analysis` | 客户 / 产品 / 区域多维 |
| 3 | 生产监控 | `ads_produce_monitor` | 产能达成率、良品率（比率用加权计算字段） |
| 4 | 生产四象限 | `ads_produce_monitor` | 车间「产能 × 良率」四象限 |
| 5 | 库存健康 | `ads_stock_health` | 单日快照（600 行）、呆滞预警 |
| 6 | 成本利润分析 | `ads_cost_profit` | 月度毛利率、成本结构 |
| 7 | 异常预警清单 | `ads_alert_warning` | 五类预警（当前 78 条） |

<details>
<summary><b>展开全部 7 张看板截图</b>（数据范围 2025-10-01 ~ 2026-09-18）</summary>

> 截图由 `python scripts\export_screenshots.py` 从 FineBI 导出的 PDF 生成（自动裁白边、统一 1434 px 宽）。
> FineBI 的仪表板级导出只有 Excel / Pdf 两个选项，所以走「导出 PDF → 转 PNG」这条路。

**1. 经营总览大屏** · 逐日快照，KPI 卡绑定「最新日期」

![经营总览大屏](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/01-boss-dashboard.png)

**2. 销售分析** · 客户 / 产品 / 区域多维

![销售分析](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/02-sale-analysis.png)

**3. 生产监控** · 产能达成率、良品率

![生产监控](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/03-produce-monitor.png)

**4. 生产四象限** · 车间产能 × 良率

![生产四象限](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/04-produce-quadrant.png)

**5. 库存健康** · 单日快照、呆滞预警

![库存健康](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/05-stock-health.png)

**6. 成本利润分析** · 月度毛利率

![成本利润分析](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/06-cost-profit.png)

**7. 异常预警清单** · 五类预警

![异常预警清单](https://cdn.jsdelivr.net/gh/q2898322792/manufacturing-dw@main/docs/screenshots/07-alert-warning.png)

</details>

---

## 常用脚本

| 脚本 | 作用 |
|---|---|
| `generate_fake_data.py` | 全量生成仿真源数据（先清 11 张源表；`--append` 可不清表） |
| `generate_incremental_data.py` | 按天补增量（默认「今天」，也可传区间回补；**逐表幂等**） |
| `etl_scheduler.py --once` | 跑一次完整 ETL（step01~step05）；跑前自检 + 跑后校验 |
| `etl_scheduler.py` | 常驻调度：先跑一次，之后每天 02:00 跑 |
  | `verify_data.py` | 数据校验：19 项断言，全通过退出码 0 |
  | `maintain_partitions.py` | 幂等补齐 DWD 事实表的**未来月份分区**（`--dry-run` 只看不动；跑批前自动调用） |
  | `build_init_sql.py` | 由分层 DDL 生成 `00_init_all.sql`；`--check` 校验是否同步 |
| `export_screenshots.py` | 看板 PDF → README 用 PNG（自动裁白边、统一宽度） |
| `render_quadrant_chart.py` | 不开 Jupyter，离线重绘四象限图 PNG |
| `repair_stock_io_dupes.py` | 清理重复出入库流水的善后工具（默认 dry-run，`--apply` 才删且先自动备份） |

---

## 数据校验与自检

跑批前后有**四道自动检查**，都挂在 `etl_scheduler.py` 上，性质不同：

| 时机 | 检查 | 失败后果 |
|---|---|---|
| 跑前 | `maintain_partitions.maintain()`：补齐事实表的未来月份分区 | ⚠️ 不阻断（分区不全会落到 `pmax`，功能仍正确） |
| 跑前 | `check_disk_space()`：MySQL `datadir` 所在盘剩余空间（默认阈值 15 GB） | ❌ **不足则中止**（爆盘是真事故，见[项目亮点](#项目亮点)第 4 条） |
| 跑前 | `build_init_sql.check()`：`00_init_all.sql` 是否与分层 DDL 同步 | ⚠️ **只打警告、不阻断**（表早已建好） |
| 跑后 | `verify_data.run()`：数据是否自洽 | ❌ **整批算失败**（数据不自洽是真问题） |

跳过开关：`--skip-partition-maintain` / `--skip-disk-check` / `--min-free-gb` / `--skip-init-check` / `--skip-verify`。

`verify_data.py` 的 19 项断言覆盖三类：

1. **规模** —— 各 ADS 表非空，并打印真实行数 / 日期范围
2. **对账** —— 营收 / 产量跨层一致：DWD = DWS = ADS
3. **一致性** —— 预警 5 类齐全且主键唯一、库存健康单一基准日、大屏逐日无断层、维度无孤儿

跳过开关：`--skip-init-check` / `--skip-verify`；单独跑：`python scripts\verify_data.py`。

---

## 常见坑（只列最容易踩的）

**FineBI 侧**

- 比率字段（%、天数）**不能求和也不能取平均** —— 用计算字段 `SUM(a)/NULLIF(SUM(b),0)` 重算
- 逐日快照表必须加日期筛选器，否则 KPI 显示的是累计值
- 抽取模式改了数据要手动「更新」，刷新浏览器没用
- 明细表要按日期降序，否则首屏永远是最老数据

**代码侧**

- `sql/01~05` 是建表脚本的唯一数据源，改完必须跑 `build_init_sql.py` 重新生成 `00_init_all.sql`
- 源库全量重建后**必须**先跑 `step00_ods_full_reset.sql`，否则 ODS 翻倍
- matplotlib 别用 U+2212「−」（真减号）—— notebook 字体 `SimHei` 无此字形，会显示成方框，用 ASCII `-`

> 完整的 10 条踩坑记录见 [`FineBI看板搭建步骤.md`](./FineBI看板搭建步骤.md) 附录 A。

---

## 已知不足与演进路线

这个项目目前定位是**可独立复现的本地 Demo**，以下是明确的短板与后续计划：

**已闭环**（曾列在这里，现已解决）：
- ✅ DWD 事实表月度 `RANGE` 分区 + 按分区增量（原「DWD 起每日全量重算」）
- ✅ MySQL binlog 保留期：用 `SET PERSIST binlog_expire_logs_seconds = 86400` 持久化
  （写进 `datadir/mysqld-auto.cnf`，重启依然生效，无需管理员改 `my.ini`）
- ✅ ODS 业务日期列索引缺失（原全表扫描）

| 不足 | 影响 | 计划 |
|---|---|---|
| **DWS / ADS 仍是全量重算**（占全流程 93% 耗时） | 日常跑批总耗时仍约 20 分钟 | DWS 按日期增量、ADS 按场景增量 |
| 维度表无代理键、无 SCD（每日全量重建） | 客户/产品属性变更时**历史会被覆盖** | 对客户、产品维度实现 SCD Type 2 拉链表 |
| `TRUNCATE PARTITION` / `TRUNCATE TABLE` 是 DDL、不可回滚 | 清理后 INSERT 失败会留下空分区/空表（**靠幂等重跑兜底**） | 改为 `EXCHANGE PARTITION`（算好临时表后原子换入） |
| 无编排平台：用 Python `schedule` | 无 DAG 依赖、无一键补数、告警仅写日志 | 迁移 DolphinScheduler，按日期参数化 + 真告警 |
| 无 Docker / CI / 单测，依赖未锁定 | 换机器复现成本高 | `docker compose` 一键起环境 + GitHub Actions + `pytest` |
| MySQL `datadir` 仍在 C 盘 | 磁盘是潜在风险（已出过一次事故，binlog 已收敛但数据盘未迁） | 迁 `datadir` 到 D 盘 |
| 数据量 5.3 GB、单机 MySQL | 匹配不了「亿级 / 实时」类岗位 | 视目标岗位补 OLAP 引擎（Doris/ClickHouse）或 CDC 实时链路 |

---

## 文档索引

| 文档 | 内容 |
|---|---|
| [`制造企业经营分析数据仓库项目说明书.docx`](./制造企业经营分析数据仓库项目说明书.docx) | 完整设计说明书（7 章：需求 / 规模 / 架构 / 源系统对接 / 数据模型 / 指标口径） |
| [`FineBI看板搭建步骤.md`](./FineBI看板搭建步骤.md) | FineBI 操作手册（表粒度铁律、7 个看板逐项、比率口径、导出截图、常见坑） |
| [`docs/PROJECT_MEMORY.md`](./docs/PROJECT_MEMORY.md) | 项目记忆：口径决策、工程约定、故障复盘、未完成事项 |
