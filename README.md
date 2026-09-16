# 制造企业经营分析数据仓库

一个基于 **MySQL + Python + FineBI** 的制造业经营分析数据仓库 Demo，完整实现「业务源库 → ODS → DWD → DWS → ADS → 可视化」五层数仓链路，配套仿真数据生成器、ETL 调度器、Jupyter 分析 Notebook 和 7 张 FineBI 看板。

---

## 架构

```
业务源库（erp_db / mes_db / wms_db，11 张表）
        │  step01  全量 + 增量同步（水位表）
        ▼
ODS 层（ods_db，11 张表）            —— 贴源、增量水位
        │  step02 / step03  清洗 + 维度建模
        ▼
DWD 层（dwd_db，7 维度 + 6 事实）    —— 明细、去重、口径统一
        │  step04  汇总
        ▼
DWS 层（dws_db，5 张汇总表）         —— 日/月粒度聚合
        │  step05  指标计算
        ▼
ADS 层（ads_db，6 张应用表）         —— 面向看板的宽表
        │
        ▼
FineBI 看板（7 个仪表板）
```

---

## 目录结构

```
data_warehouse_project/
├── sql/
│   ├── 01_source_ddl/      # 源库建表（erp_db / mes_db / wms_db，11 张）
│   ├── 02_ods_db/          # ODS 贴源层（11 张）
│   ├── 03_dwd_db/          # DWD 明细层（7 维度 + 6 事实）
│   ├── 04_dws_db/          # DWS 汇总层（5 张）
│   ├── 05_ads_db/          # ADS 应用层（6 张）
│   ├── 06_etl_scripts/     # ETL 脚本（step00~step05）
│   ├── 数据查询/           # 手工查询 / 脏数据探查
│   └── _backup_20260910/   # 2026-09-10 改脚本前的备份
├── scripts/                # 数据生成 + ETL 调度（Python）
├── notebooks/              # Jupyter 分析（RFM、产能质量四象限）
├── logs/                   # ETL 运行日志（运行时生成，不进库）
├── bl/                     # FineBI 看板导出 PDF（不进库）
├── _bi_review/             # 看板复核临时产物 OCR/截图（可删，不进库）
└── 制造企业经营分析数据仓库项目说明书（V2.1 完整实施版）.docx
```

---

## 环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| Python | 3.10+ | 脚本 + Notebook |
| MySQL | 8.x | 源库 + 五层数仓库 |
| FineBI | 6.0 | 看板（连 `ads_db`） |
| Python 依赖 | 见 `requirements.txt` | `pip install -r requirements.txt` |

数据库连接默认 `root / root @ localhost:3306`，可用环境变量覆盖：`DB_HOST`、`DB_PORT`、`DB_USER`、`DB_PASSWORD`。

---

## 快速开始

```powershell
cd D:\data_warehouse_project

# 1) 安装依赖
pip install -r requirements.txt

# 2) 首次初始化：建 7 个库 + 全部分层表（幂等，可重复执行）
#    sql/00_init_all.sql 是产物，由各层 DDL 自动生成；
#    改了 sql/01~05 里的建表脚本后要重新生成，否则两边会漂移：
#      python scripts\build_init_sql.py            # 重新生成
#      python scripts\build_init_sql.py --check    # 只校验是否同步（不同步退出码 1）
mysql -uroot -p < sql\00_init_all.sql

# 3) 全量重建源数据（会先清空源库 11 张表，约 40~90 分钟）
python scripts\generate_fake_data.py

# 4) 【仅源库全量重建后必须执行一次】清空 ODS + 重置增量水位
#    用 MySQL 客户端执行 sql/06_etl_scripts/step00_ods_full_reset.sql
#    否则 step01 会把新数据当增量追加，导致 ODS 翻倍

# 5) 跑 ETL 全流程（step01~step05，约 20~30 分钟）
python scripts\etl_scheduler.py --once

# 6) 之后每天补增量（默认只生成"今天"）
python scripts\generate_incremental_data.py
#    或回补区间缺口（已有数据的日期自动跳过）
python scripts\generate_incremental_data.py 2026-07-01 2026-09-10

# 7) FineBI：数据 → 分析主题 → 更新 → 浏览器 Ctrl+F5
```

> 注意：**只跑生成器不跑 ETL，看板不会变**；第 3 步会清空源表，请确认没有其他程序在读这三个库。

---

## 数据分层

| 层 | 库 | 表数 | 职责 |
|---|---|---|---|
| 源库 | erp_db / mes_db / wms_db | 11 | 业务仿真数据 |
| ODS | ods_db | 11 | 贴源、增量同步（水位表 `etl_watermark`） |
| DWD | dwd_db | 7 维度 + 6 事实 | 清洗、去重、统一口径 |
| DWS | dws_db | 5 | 日/月粒度聚合 |
| ADS | ads_db | 6 | 面向看板的指标宽表 |

---

## 看板清单（FineBI）

| # | 看板 | 数据源 | 说明 |
|---|---|---|---|
| 1 | 经营总览大屏 | ads_boss_dashboard | 逐日快照，**必须加日期筛选器** |
| 2 | 销售分析 | ads_sale_analysis | 客户/产品/区域多维 |
| 3 | 生产监控 | ads_produce_monitor | 产能达成率、良品率 |
| 4 | 生产四象限 | ads_produce_monitor | 车间产能×良率四象限 |
| 5 | 库存健康 | ads_stock_health | 单日快照、呆滞预警 |
| 6 | 成本利润分析 | ads_cost_profit | 月度毛利率 |
| 7 | 异常预警清单 | ads_alert_warning | 五类预警 |

---

## 常用脚本

| 脚本 | 作用 |
|---|---|
| `scripts/generate_fake_data.py` | 全量生成仿真源数据（会先清空 11 张源表，约 40~90 分钟） |
| `scripts/generate_incremental_data.py` | 按天补增量（默认"今天"，也可传区间回补） |
| `scripts/etl_scheduler.py --once` | 跑一次完整 ETL（step01~step05，约 20~30 分钟） |
| `scripts/etl_scheduler.py` | 常驻调度：先跑一次，之后每天 02:00 跑 |
| `scripts/build_init_sql.py` | 由各层 DDL 生成 `sql/00_init_all.sql`；`--check` 校验是否同步 |
| `scripts/render_quadrant_chart.py` | 不开 Jupyter，离线重绘四象限图 PNG |

> 所有脚本的数据库连接都读环境变量 `DB_HOST / DB_PORT / DB_USER / DB_PASSWORD`，默认 `root/root@localhost:3306`。

---

## 文档索引

- [FineBI看板重建步骤.md](./FineBI看板重建步骤.md) —— 看板搭建操作手册（点哪里，含 6 个常踩坑）
- [BI看板数据修正说明.md](./BI看板数据修正说明.md) —— 数据口径修正记录 + 三次故障复盘
- 制造企业经营分析数据仓库项目说明书（V2.1 完整实施版）.docx —— 完整设计说明书

---

## 常见坑（详见《FineBI看板重建步骤》附录）

1. 比率字段（%、天数）用了「求和」——天级快照表求和 = 累计值，不是当天值
2. 快照表没加日期筛选器
3. 明细表没按日期倒序（首屏永远是最老数据）
4. 抽取模式忘了点「更新」
5. TOP N 忘了设排序
6. 计算字段漏了分母保护（`SUM(a)/NULLIF(SUM(b),0)`）

### 代码层的一个坑（matplotlib 字体）

**图里别用 U+2212「−」（真减号）**。notebook 用的字体是 `SimHei`（GB2312 系），**没有这个字形**，图上会显示成方框 `□`，例如标题变成"产能达成率 □ 80% 标准"。用 ASCII 连字符 `-` 即可。

> 排查提示：`scripts/render_quadrant_chart.py` 刻意使用与 notebook **完全相同**的字体配置，
> 就是为了让离线预览能暴露这类字体缺字形问题——不要把它换成字形更全的字体，那样会把问题掩盖掉。
