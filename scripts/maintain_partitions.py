#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DWD 事实表 · 月度分区维护
====================================================
背景：
    DWD 的 6 张事实表按业务日期做了**月度 RANGE 分区**，并留了一个 `pmax (MAXVALUE)`
    兜底分区。新数据如果落在 `pmax` 里，就失去了分区剪枝的意义（所有未来数据挤在一个分区）。

本脚本负责**自动补未来月份的分区**：
    对每张表，把"当前月 ~ 未来 @AHEAD 个月"之间缺失的分区一次性补上。

为什么用 REORGANIZE 而不是 ADD PARTITION：
    分区列表末尾是 `pmax (MAXVALUE)`，MySQL 不允许在 MAXVALUE 之后再 ADD PARTITION，
    必须把 `pmax` 拆开（REORGANIZE PARTITION pmax INTO (新分区..., pmax)）。

用法：
    python scripts\\maintain_partitions.py            # 检查并补齐
    python scripts\\maintain_partitions.py --dry-run  # 只看要改什么，不执行
    python scripts\\maintain_partitions.py --ahead 6  # 往后备 6 个月（默认 3）

说明：
    · 幂等：已存在的分区不会重复创建；无缺失时什么都不做
    · 已被 etl_scheduler.py 在每轮 ETL 前自动调用（--skip-partition-maintain 可关闭）
    · 分区列是 VARCHAR 'YYYY-MM' 的表（dwd_cost_detail），按字符串边界分区
"""

import os
import sys
import argparse
import logging

import pymysql

DB_CONFIG = {
    'host': os.environ.get('DB_HOST', '127.0.0.1'),
    'port': int(os.environ.get('DB_PORT', '3306')),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', 'root'),
    'charset': 'utf8mb4',
}

# 表名 -> (分区列, 是否月份字符串)
PARTITIONED = {
    'dwd_sale_order_detail':        ('order_date',    False),
    'dwd_produce_workorder_detail': ('plan_start_date', False),
    'dwd_stock_io_detail':          ('io_date',       False),
    'dwd_stock_snapshot':           ('snapshot_date', False),
    'dwd_cost_detail':              ('cost_month',    True),
    'dwd_equipment_runtime':        ('record_date',   False),
}

AHEAD = 3          # 往后预建几个月
SCHEMA = 'dwd_db'


def month_seq(start_y, start_m, n):
    """从 (start_y, start_m) 开始的 n 个月，返回 [(y,m), ...]"""
    out = []
    y, m = start_y, start_m
    for _ in range(n):
        out.append((y, m))
        m += 1
        if m > 12:
            y, m = y + 1, 1
    return out


def bound(y, m, is_str):
    """该分区的上界（LESS THAN）：月字符串表用 'YYYY-MM'，日期表用 'YYYY-MM-01' 的次月"""
    ny, nm = (y + 1, 1) if m == 12 else (y, m + 1)
    return '%04d-%02d' % (ny, nm) if is_str else '%04d-%02d-01' % (ny, nm)


def pname(y, m):
    return 'p%04d%02d' % (y, m)


def maintain(ahead=AHEAD, dry_run=False, logger=None):
    """补齐未来分区。返回 (是否有变更, 变更的表数, 说明行列表)"""
    log = logger or logging.getLogger('partition')
    conn = pymysql.connect(**DB_CONFIG)
    cur = conn.cursor()
    changed_tables = 0
    lines = []

    # 基准月：取各表分区列的最大值所在月，与"当前月"取较大者
    for tbl, (col, is_str) in PARTITIONED.items():
        cur.execute("""SELECT partition_name FROM information_schema.partitions
                       WHERE table_schema=%s AND table_name=%s AND partition_name IS NOT NULL""",
                    (SCHEMA, tbl))
        exist = {r[0] for r in cur.fetchall()}
        if not exist:
            lines.append('⚠️ %s 不是分区表（或不存在），跳过' % tbl)
            continue

        # 当前月
        cur.execute("SELECT YEAR(CURDATE()), MONTH(CURDATE())")
        cy, cm = cur.fetchone()
        # 数据最大日期所在月（可能超过当前月，例如成本凭证按月铺数据）
        cur.execute("SELECT MAX(%s) FROM %s.%s" % (col, SCHEMA, tbl))
        mx = cur.fetchone()[0]
        if mx is not None:
            s = str(mx)
            dy, dm = int(s[:4]), int(s[5:7])
            if (dy, dm) > (cy, cm):
                cy, cm = dy, dm

        want = month_seq(cy, cm, ahead + 1)                 # 含当前月，共 ahead+1 个
        missing = [(y, m) for (y, m) in want if pname(y, m) not in exist]
        if not missing:
            lines.append('✅ %-30s 未来 %d 个月分区已齐全，无需变更' % (tbl, ahead + 1))
            continue

        parts = ',\n    '.join(
            "PARTITION %s VALUES LESS THAN ('%s')" % (pname(y, m), bound(y, m, is_str))
            for (y, m) in missing)
        sql = ("ALTER TABLE %s.%s REORGANIZE PARTITION pmax INTO (\n    %s,\n"
               "    PARTITION pmax VALUES LESS THAN (MAXVALUE)\n);" % (SCHEMA, tbl, parts))

        if dry_run:
            lines.append('🔎 %-30s 待新增 %d 个分区：%s'
                         % (tbl, len(missing), ', '.join(pname(y, m) for y, m in missing)))
        else:
            cur.execute(sql)
            conn.commit()
            changed_tables += 1
            lines.append('✅ %-30s 已新增 %d 个分区：%s'
                         % (tbl, len(missing), ', '.join(pname(y, m) for y, m in missing)))

    conn.close()
    for l in lines:
        log.info(l)
    return changed_tables > 0, changed_tables, lines


def main():
    ap = argparse.ArgumentParser(description='DWD 事实表月度分区维护')
    ap.add_argument('--ahead', type=int, default=AHEAD, help='往后预建几个月，默认 %d' % AHEAD)
    ap.add_argument('--dry-run', action='store_true', help='只检查，不执行 ALTER')
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(message)s')
    print('=' * 62)
    print('DWD 事实表 · 月度分区维护%s' % ('（dry-run）' if args.dry_run else ''))
    print('=' * 62)
    ok, n, _ = maintain(ahead=args.ahead, dry_run=args.dry_run, logger=logging.getLogger())
    print('-' * 62)
    print('处理完成：%d 张表发生了变更' % n)
    return 0


if __name__ == '__main__':
    sys.exit(main())
