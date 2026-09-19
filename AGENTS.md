# AGENTS.md

> 给所有 coding agent（WorkBuddy / CodeBuddy、Claude Code、Codex…）的入口提示。
> 接手本仓库前，**先读 `docs/PROJECT_MEMORY.md`** —— 那里记录了口径决策、工程约定、
> 历史故障复盘与未完成事项。
> 怎么跑见 `README.md`；看板怎么搭见 `FineBI看板搭建步骤.md`。

## 三条最容易踩的雷

1. **全量重建源数据的顺序不能乱**：`generate_fake_data.py` → `sql/06_etl_scripts/step00_ods_full_reset.sql` → `etl_scheduler.py --once`。
   漏掉 step00，ODS 会翻倍，磁盘可能被写满。
2. **建表脚本的唯一数据源是 `sql/01~05`**。改了 DDL 必须跑 `python scripts\build_init_sql.py` 重新生成 `sql/00_init_all.sql`（它是生成物，勿手改）。
3. **看板聚合看表粒度**：`ads_boss_dashboard` 是逐日快照（353 行），KPI 卡不能直接求和，必须加日期筛选器。

## 提交前

```powershell
python scripts\build_init_sql.py --check   # 建表脚本是否同步
python scripts\verify_data.py              # 19 项数据断言
```

数据库连接一律读环境变量 `DB_HOST / DB_PORT / DB_USER / DB_PASSWORD`（默认 `root/root@localhost:3306`），不要写死密码。
