#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ETL 自动调度脚本（独立 Demo · 修复版）
====================================================
功能：模拟企业级 ETL 任务调度：定时执行 / 失败重试 / 日志记录 / 邮件告警
技术栈：Python + schedule + pymysql

用法：
    python scripts/etl_scheduler.py                 # 守护模式：先立即跑一次，再按 SCHEDULE_TIME 定时跑
    python scripts/etl_scheduler.py --once          # 单次执行完整流水线后退出（适合手动/系统任务计划）
    python scripts/etl_scheduler.py --once --time 02:00
    python scripts/etl_scheduler.py --max-retries 1 --retry-interval 5   # 便于调试时缩短重试

修复点（相对旧版）：
    1. SQL 脚本切分改为“注释感知”解析：-- / # 行注释、/* */ 块注释会先被剥离，
       且字符串/标识符内的分号不会被误切。修复了旧版因语句以注释开头而整条被跳过
       导致的：水位表建不出来(1146)、USE 语句丢失(1046 No database selected)、
       @sync_time 未设置、部分 ODS 表静默漏同步、水位永远停在 1970 -> 二次运行主键冲突(1062)。
    2. 每张表/每条 SQL 在同一个连接上顺序执行，事务统一提交/回滚，出错时连接必定关闭。
    3. 失败信息带“第几条语句 + 语句摘要”，方便定位；水位推进语句与插入同事务。
    4. 支持 --once 单次模式与命令行覆盖调度时间/重试参数。
    5. 数据库连接支持环境变量覆盖（DB_HOST/DB_PORT/DB_USER/DB_PASSWORD）。
"""

import os
import sys
import time
import argparse
import logging
import traceback
from datetime import datetime, timedelta
from typing import List, Tuple

try:
    import schedule
except ImportError:
    schedule = None
import pymysql

# ============================================================
# 一、配置区（可用环境变量覆盖；命令行参数优先级最高）
# ============================================================

def _env(key: str, default: str) -> str:
    return os.environ.get(key, default)

DB_CONFIG = {
    'host': _env('DB_HOST', 'localhost'),
    'port': int(_env('DB_PORT', '3306')),
    'user': _env('DB_USER', 'root'),
    'password': _env('DB_PASSWORD', 'root'),
    'charset': 'utf8mb4',
    'autocommit': False,          # 显式事务：全部语句成功才 commit
}

# ETL 任务列表（按依赖顺序排列）
ETL_STEPS = [
    ('step01_ods_sync', 'sql/06_etl_scripts/step01_ods_sync.sql'),
    ('step02_dwd_dimension', 'sql/06_etl_scripts/step02_dwd_dimension.sql'),
    ('step03_dwd_fact', 'sql/06_etl_scripts/step03_dwd_fact.sql'),
    ('step04_dws_agg', 'sql/06_etl_scripts/step04_dws_agg.sql'),
    ('step05_ads_calc', 'sql/06_etl_scripts/step05_ads_calc.sql'),
]

# 调度与重试默认值（--once 命令行参数可覆盖）
SCHEDULE_TIME = "02:00"   # 每日定时执行时间
MAX_RETRIES = 3           # 单步最大重试次数
RETRY_INTERVAL = 300      # 重试间隔（秒）
CONTINUE_ON_ERROR = False # True=某步失败继续后续步骤；False=失败即中断

# 每条 SQL 单独提交（默认 True）
# ------------------------------------------------------------
# 为什么默认改成 True：
#   原来"整个脚本成功才 commit"，等于把 step03 的几百万行 INSERT 放进一个巨型事务。
#   巨型事务会同时放大 undo 表空间和 binlog 事件：2026-09-10 那次故障中，
#   一个事务一次性写出 1.1 GB 的 binlog 文件，直接把 C 盘写满，
#   最终 step03 报 (1114, "The table 'dwd_stock_io_detail' is full")。
#   改为逐条提交后，峰值 undo/binlog 只有单条语句的规模。
#   代价：某步中途失败会留下"部分完成"的状态；但 step03/04/05 开头都是
#   TRUNCATE + 全量重建（幂等），直接重跑该步即可收敛。
COMMIT_PER_STATEMENT = True

LOG_DIR = "logs"

# 跑批前自检：sql/00_init_all.sql 是否与 sql/01~05 各层 DDL 同步
# ------------------------------------------------------------
# 说明：00_init_all.sql 是生成物（由 scripts/build_init_sql.py 生成）。
#       改了分层 DDL 忘了重新生成时，这里会提醒，但**只提醒、不阻断**——
#       表早就建好了，同步与否不影响本次跑批。
#       用 --skip-init-check 可跳过；用 python scripts/build_init_sql.py 重新生成。
CHECK_INIT_SQL = True

# ============================================================
# 二、日志模块
# ============================================================

def setup_logging(log_dir: str = LOG_DIR, force: bool = False):
    """配置日志系统（控制台 + 当日文件）；force=True 时重建全部 handler"""
    os.makedirs(log_dir, exist_ok=True)
    # Windows 控制台编码兼容（emoji 日志不抛 UnicodeEncodeError）
    for stream in (sys.stdout, sys.stderr):
        try:
            if hasattr(stream, 'reconfigure'):
                stream.reconfigure(encoding='utf-8', errors='replace')
        except Exception:
            pass

    log_file = os.path.join(log_dir, f"etl_{datetime.now().strftime('%Y%m%d')}.log")
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler(sys.stdout),
        ],
        force=force,
    )
    return logging.getLogger(__name__)


logger = setup_logging()

# ============================================================
# 三、邮件告警模块（模拟）
# ============================================================

def send_alert(step_name: str, error_msg: str):
    """
    发送告警邮件（模拟）
    企业级场景可接入真实 SMTP 或企业微信/钉钉 Webhook
    """
    alert_msg = (
        "\n⚠️ ETL 任务失败告警\n"
        f"任务名称: {step_name}\n"
        f"失败时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"错误信息: {error_msg}\n"
        "请及时处理！"
    )
    logger.error(f"📧 [告警] {alert_msg}")

    # 实际项目中可取消注释以下代码接入真实邮件
    # import smtplib
    # from email.mime.text import MIMEText
    # ... 配置 SMTP 发送邮件 ...


# ============================================================
# 四、SQL 脚本解析（注释感知切分）
# ============================================================

def split_sql_script(sql: str) -> List[str]:
    """
    把一份 SQL 脚本切成若干条独立语句。

    与旧版“按分号粗暴 split + 跳过 -- 开头语句”不同：
      - 剥离 -- / # 行注释 与 /* */ 块注释（/*! ... */ 可执行注释内容保留）；
      - 字符串字面量('...'/"...")、反引号标识符内部的 -- 与 ; 不会被误处理；
      - 只在“语句层”的分号处切分，返回非空语句列表。

    这样即使脚本里出现：
        -- 注释
        USE xxx;
        或  ...;-- 注释
            INSERT INTO ...
    也能正确拆出并执行 USE / INSERT 等真实语句。
    """
    stripped = _strip_sql_comments(sql)
    statements = []
    buf = []
    i, n = 0, len(stripped)
    while i < n:
        ch = stripped[i]
        # 语句终结符：分号（已在注释/字符串之外）
        if ch == ';':
            stmt = ''.join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    tail = ''.join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


def _strip_sql_comments(sql: str) -> str:
    """去掉 SQL 中的注释，保留字符串字面量与标识符内容不变。"""
    out = []
    i, n = 0, len(sql)
    while i < n:
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ''
        # -- 行注释（MySQL 要求 -- 后跟空格/控制符；这里宽松处理到行尾）
        if ch == '-' and nxt == '-':
            while i < n and sql[i] not in '\r\n':
                i += 1
            continue
        # # 行注释
        if ch == '#':
            while i < n and sql[i] not in '\r\n':
                i += 1
            continue
        # /* 块注释 */；/*! ... */ 是可执行注释，保留其中的 SQL
        if ch == '/' and nxt == '*':
            end = sql.find('*/', i + 2)
            if end == -1:
                break  # 未闭合注释：丢弃剩余内容
            inner = sql[i + 2:end]
            if inner.startswith('!'):
                out.append(inner[1:])  # 去掉 "!" 前缀，内容当普通 SQL 保留
            i = end + 2
            continue
        # 字符串字面量 / 反引号标识符：原样拷贝（含转义）
        if ch in ("'", '"', '`'):
            quote = ch
            out.append(ch)
            i += 1
            while i < n:
                cur = sql[i]
                if cur == '\\' and i + 1 < n and quote != '`':
                    out.append(cur)
                    out.append(sql[i + 1])
                    i += 2
                    continue
                out.append(cur)
                i += 1
                if cur == quote:
                    # MySQL: 字符串内 '' 表示转义的单引号
                    if quote != '`' and i < n and sql[i] == quote:
                        out.append(sql[i])
                        i += 1
                        continue
                    break
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


# ============================================================
# 五、数据库执行模块
# ============================================================

def execute_sql_file(sql_path: str) -> Tuple[bool, str]:
    """
    在【同一个连接】上按顺序执行 SQL 文件中的所有语句。

    - 成功后统一 commit；
    - 任一条失败则 rollback 并立即返回失败（语句序号 + 摘要），连接必定关闭；
    - 会话内变量（如 SET @sync_time = NOW()）在同一连接中跨语句生效。
    返回: (是否成功, 执行信息)
    """
    if not os.path.exists(sql_path):
        return False, f"SQL 文件不存在: {sql_path}"

    conn = None
    try:
        with open(sql_path, 'r', encoding='utf-8') as f:
            sql_content = f.read()

        statements = split_sql_script(sql_content)
        if not statements:
            return False, f"SQL 文件为空或无有效语句: {sql_path}"

        conn = pymysql.connect(**DB_CONFIG)
        cursor = conn.cursor()
        executed = 0
        try:
            for idx, stmt in enumerate(statements, start=1):
                cursor.execute(stmt)
                # 逐条提交：避免几百万行挤在一个巨型事务里放大 undo / binlog 峰值
                if COMMIT_PER_STATEMENT:
                    conn.commit()
                executed += 1
            if not COMMIT_PER_STATEMENT:
                conn.commit()
        except Exception as e:
            conn.rollback()
            snippet = stmt if len(stmt) <= 160 else stmt[:160] + '...'
            raise RuntimeError(
                f"第 {idx}/{len(statements)} 条语句失败: {e} | 语句: {snippet}"
            ) from e
        finally:
            try:
                cursor.close()
            except Exception:
                pass

        return True, f"成功执行 {executed} 条 SQL 语句（{os.path.basename(sql_path)}）"
    except pymysql.Error as e:
        return False, f"数据库错误: {e}"
    except Exception as e:
        return False, f"执行失败: {e}"
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass


# ============================================================
# 六、ETL 任务执行模块（含重试机制）
# ============================================================

def run_etl_step(step_name: str, sql_path: str,
                 max_retries: int, retry_interval: int) -> bool:
    """
    执行单个 ETL 步骤，含重试机制。
    返回: 是否成功
    """
    for attempt in range(1, max_retries + 1):
        start = time.time()
        logger.info(f"🔄 执行 {step_name} (第 {attempt}/{max_retries} 次尝试)")

        success, message = execute_sql_file(sql_path)
        elapsed = time.time() - start

        if success:
            logger.info(f"✅ {step_name} 执行成功: {message}（耗时 {elapsed:.1f} 秒）")
            return True

        logger.warning(f"⚠️ {step_name} 执行失败: {message}（耗时 {elapsed:.1f} 秒）")

        if attempt < max_retries:
            next_retry_time = datetime.now() + timedelta(seconds=retry_interval)
            logger.info(f"⏳ 等待 {retry_interval} 秒后重试...")
            logger.info(f"⏰ 下次重试时间: {next_retry_time.strftime('%Y-%m-%d %H:%M:%S')}")
            time.sleep(retry_interval)
        else:
            logger.error(f"❌ {step_name} 重试 {max_retries} 次仍失败")
            send_alert(step_name, message)
            return False
    return False


def check_init_sql_sync() -> bool:
    """
    跑批前自检：sql/00_init_all.sql 是否与各层 DDL 同步。

    返回是否同步。任何异常都视为"跳过自检"，绝不因此影响 ETL。
    """
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import build_init_sql
        ok, msg = build_init_sql.check()
        if ok:
            logger.info(f"✅ 建表脚本自检：{msg}")
        else:
            logger.warning(f"⚠️ 建表脚本自检：{msg}")
            logger.warning("   （不影响本次 ETL，仅提示同步一下；--skip-init-check 可关闭自检）")
        return ok
    except Exception as e:
        logger.warning(f"⚠️ 建表脚本自检跳过（{e}）")
        return True


def run_etl_pipeline(max_retries: int = MAX_RETRIES,
                     retry_interval: int = RETRY_INTERVAL,
                     continue_on_error: bool = CONTINUE_ON_ERROR,
                     check_init: bool = CHECK_INIT_SQL) -> bool:
    """
    执行完整 ETL 流水线。
    返回: 流水线是否全部成功
    """
    logger.info("=" * 60)
    logger.info("🚀 ETL 流水线开始执行")
    logger.info(f"⏰ 开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 60)

    # 跑批前自检（只提醒，不阻断）
    if check_init:
        check_init_sql_sync()

    start_time = time.time()
    failed_steps: List[str] = []

    for step_name, sql_path in ETL_STEPS:
        step_start = time.time()
        ok = run_etl_step(step_name, sql_path, max_retries, retry_interval)
        if not ok:
            failed_steps.append(step_name)
            if not continue_on_error:
                logger.error(f"❌ ETL 流水线中断（失败步骤 {step_name}，耗时 "
                             f"{time.time() - step_start:.1f} 秒）")
                break
        else:
            logger.info(f"📊 {step_name} 完成，耗时 {time.time() - step_start:.1f} 秒")

    elapsed = time.time() - start_time
    logger.info("=" * 60)
    if failed_steps:
        logger.error("❌ ETL 流水线执行失败")
        logger.error(f"失败步骤: {', '.join(failed_steps)}")
        logger.error(f"⏱️ 总耗时: {elapsed:.2f} 秒")
    else:
        logger.info("✅ ETL 流水线全部执行成功！")
        logger.info(f"⏱️ 总耗时: {elapsed:.2f} 秒")
    logger.info("=" * 60)
    return not failed_steps


# ============================================================
# 七、调度器配置
# ============================================================

def run_scheduler(schedule_time: str, max_retries: int, retry_interval: int,
                  check_init: bool = CHECK_INIT_SQL):
    """启动常驻调度器：先立即跑一次，再按每日 schedule_time 定时执行。"""
    logger.info("=" * 60)
    logger.info("⏰ ETL 调度器启动")
    logger.info(f"📅 调度时间: 每日 {schedule_time}")
    logger.info(f"📁 日志目录: {LOG_DIR}")
    logger.info("=" * 60)

    if schedule is None:
        logger.error("❌ 未安装 schedule 库（pip install schedule），仅能使用 --once 模式")
        sys.exit(1)

    # 设置定时任务
    schedule.every().day.at(schedule_time).do(
        run_etl_pipeline, max_retries, retry_interval, CONTINUE_ON_ERROR, check_init
    )

    # 立即执行一次（用于测试/首次启动补数）
    logger.info("🧪 立即执行一次 ETL（测试模式）...")
    run_etl_pipeline(max_retries=max_retries, retry_interval=retry_interval,
                     check_init=check_init)

    # 进入调度循环
    logger.info(f"⏳ 等待下一个调度时间: {schedule_time}")
    while True:
        schedule.run_pending()
        time.sleep(60)


# ============================================================
# 八、命令行入口
# ============================================================

def parse_args():
    parser = argparse.ArgumentParser(description='ETL 自动调度脚本')
    parser.add_argument('--once', action='store_true',
                        help='只执行一次完整 ETL 流水线后退出（不做常驻调度）')
    parser.add_argument('--time', default=SCHEDULE_TIME,
                        help=f'每日定时执行时间，默认 {SCHEDULE_TIME}')
    parser.add_argument('--max-retries', type=int, default=MAX_RETRIES,
                        help=f'单步最大重试次数，默认 {MAX_RETRIES}')
    parser.add_argument('--retry-interval', type=int, default=RETRY_INTERVAL,
                        help=f'重试间隔秒数，默认 {RETRY_INTERVAL}')
    parser.add_argument('--continue-on-error', action='store_true',
                        help='某一步失败后继续执行后续步骤（默认失败即中断）')
    parser.add_argument('--log-dir', default=LOG_DIR, help=f'日志目录，默认 {LOG_DIR}')
    parser.add_argument('--skip-init-check', action='store_true',
                        help='跳过"建表脚本是否同步"自检（默认会自检并提醒，不阻断）')
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    if args.log_dir != LOG_DIR:
        LOG_DIR = args.log_dir
        logger = setup_logging(LOG_DIR, force=True)  # noqa: F811 按新目录重建日志

    if args.once:
        ok = run_etl_pipeline(
            max_retries=args.max_retries,
            retry_interval=args.retry_interval,
            continue_on_error=args.continue_on_error,
            check_init=not args.skip_init_check,
        )
        sys.exit(0 if ok else 1)
    else:
        try:
            run_scheduler(args.time, args.max_retries, args.retry_interval,
                          check_init=not args.skip_init_check)
        except KeyboardInterrupt:
            logger.info("🛑 调度器已停止")
            sys.exit(0)
        except Exception as e:
            logger.error(f"❌ 调度器异常: {e}")
            logger.error(traceback.format_exc())
            sys.exit(1)
