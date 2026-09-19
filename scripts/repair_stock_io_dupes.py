#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
出入库流水「重复行」清理工具
====================================================
背景（2026-09-18 事故）：
    generate_incremental_data.py 旧版只用 erp_db.sale_order 判断
    "这天是否已经生成过"，而各源表的日期覆盖并不一致——库存快照 / 出入库
    在源库全量生成时被多铺了一个月（到 2026-07-31），销售订单只到 2026-06-30。
    于是回补 7 月时被判定为"没有数据"，重复执行生成：
      · wms_db.stock_snapshot 撞唯一键 uk_material_warehouse_date → 报 1062；
      · 但 wms_db.stock_io_detail **没有业务唯一键**（主键是 UUID io_id），
        流水已经插入并提交 → 该日出入库行数翻倍（约 1500 → 约 3000）。
    更麻烦的是 batch_insert 内部逐批 commit，外层的 conn.rollback() 救不回来。

本脚本做什么：
    把"生成事故当天新建的那些重复流水行"删掉，把出入库恢复到事故前的状态。
    识别方式：io_date 在指定区间内，且 create_time 落在事故当天。
    （历史数据是 2026-09-16 全量生成时写入的，create_time 自然不同，不会误删。）

    同时清理 ods_db.ods_wms_stock_io 中的同一批行——step01 是按 update_time 增量
    同步的，源库删行不会自动传播，若这期间已经跑过 ETL，重复行会残留在 ODS。

安全设计：
    · **默认 dry-run**：只统计并打印，不删任何数据；要真正执行必须加 --apply；
    · 先备份：把待删行整行写入 wms_db.stock_io_dupe_bak_<日期>，备份为空则中止；
    · 逐日护栏：删除后若该日将变成 0 行，则跳过该日（宁可少删，不可清空）；
    · 输出每天删除前后的行数对比。

用法：
    python scripts/repair_stock_io_dupes.py                          # 预览（默认 2026-07-01~2026-07-31）
    python scripts/repair_stock_io_dupes.py --apply                  # 真正执行
    python scripts/repair_stock_io_dupes.py 2026-07-01 2026-07-31 --apply
    python scripts/repair_stock_io_dupes.py --created-on 2026-09-18 --apply

删完记得重跑 ETL，让 DWD / DWS / ADS 重新消费清洗后的源数据：
    python scripts/etl_scheduler.py --once
"""

import argparse
import datetime
import os
import sys

import pymysql

SRC = 'wms_db.stock_io_detail'
ODS = 'ods_db.ods_wms_stock_io'


def connect():
    return pymysql.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=int(os.environ.get('DB_PORT', '3306')),
        user=os.environ.get('DB_USER', 'root'),
        password=os.environ.get('DB_PASSWORD', 'root'),
        charset='utf8mb4')


def table_exists(cur, full_name):
    db, tbl = full_name.split('.')
    cur.execute("SELECT COUNT(*) FROM information_schema.tables "
                "WHERE table_schema=%s AND table_name=%s", (db, tbl))
    return cur.fetchone()[0] > 0


def stats_by_day(cur, table, start, end, created_on):
    """返回 {日期: (总行数, 事故当天写入的行数)}"""
    cur.execute(
        "SELECT io_date, COUNT(*) AS total, "
        "       SUM(DATE(create_time) = %s) AS dupe "
        "FROM " + table + " "
        "WHERE io_date BETWEEN %s AND %s "
        "GROUP BY io_date ORDER BY io_date",
        (created_on, start, end))
    return {row[0]: (int(row[1]), int(row[2] or 0)) for row in cur.fetchall()}


def in_clause(dates):
    return 'io_date IN (%s)' % ', '.join(['%s'] * len(dates))


def main():
    ap = argparse.ArgumentParser(description='清理出入库流水中由重复生成产生的重复行')
    ap.add_argument('start', nargs='?', default='2026-07-01', help='起始日期，默认 2026-07-01')
    ap.add_argument('end', nargs='?', default='2026-07-31', help='结束日期，默认 2026-07-31')
    ap.add_argument('--created-on', default=datetime.date.today().isoformat(),
                    help='重复行的 create_time 日期，默认为今天')
    ap.add_argument('--apply', action='store_true', help='真正执行删除（默认只预览）')
    args = ap.parse_args()

    start = datetime.datetime.strptime(args.start, '%Y-%m-%d').date()
    end = datetime.datetime.strptime(args.end, '%Y-%m-%d').date()
    created_on = datetime.datetime.strptime(args.created_on, '%Y-%m-%d').date()

    conn = connect()
    cur = conn.cursor()

    print('=' * 64)
    print('出入库重复行清理')
    print(f'  区间      : {start} ~ {end}')
    print(f'  重复行标记: create_time 的日期 = {created_on}')
    print(f'  模式      : {"【执行删除】" if args.apply else "预览（dry-run，不会改动数据）"}')
    print('=' * 64)

    before = stats_by_day(cur, SRC, start, end, created_on)
    if not before:
        print(f'\n源表在 {start} ~ {end} 没有任何行，无需处理。')
        return 0

    print('\n[源表 wms_db.stock_io_detail] 每日行数（总行数 / 事故当天写入）')
    safe_dates, total_dupe, skipped = [], 0, []
    for d, (total, dupe) in before.items():
        flag = ''
        if dupe:
            left = total - dupe
            if left <= 0:
                flag = '  ⚠️ 删除后会清空该日 → 跳过'
                skipped.append(d)
            else:
                safe_dates.append(d)
                total_dupe += dupe
                if left < 200:
                    flag = '  ⚠️ 删除后剩余偏少，请人工确认'
        print(f'  {d}  {total:>6} / {dupe:>6}{flag}')
    print(f'  ── 合计待删 {total_dupe:,} 行，涉及 {len(safe_dates)} 天')
    if skipped:
        print(f'  ── 因护栏跳过 {len(skipped)} 天：{", ".join(str(x) for x in skipped)}')

    if not total_dupe:
        print('\n没有可删除的重复行。')
        print('若确认存在重复，请用 --created-on 指定事故发生日期后重试。')
        return 0

    if not args.apply:
        print('\n以上为预览。确认无误后加 --apply 执行删除。')
        print('执行前会自动备份到 wms_db.stock_io_dupe_bak_<日期>。')
        return 0

    # ---------------- 真正执行 ----------------
    bak = f'wms_db.stock_io_dupe_bak_{created_on.strftime("%Y%m%d")}'
    where = f'{in_clause(safe_dates)} AND DATE(create_time) = %s'
    date_params = [d for d in safe_dates] + [created_on]

    print(f'\n[1/4] 备份待删行 → {bak}')
    cur.execute(f'DROP TABLE IF EXISTS {bak}')
    cur.execute(f'CREATE TABLE {bak} AS SELECT * FROM {SRC} WHERE {where}', date_params)
    conn.commit()
    cur.execute(f'SELECT COUNT(*) FROM {bak}')
    backed = cur.fetchone()[0]
    print(f'      已备份 {backed:,} 行')
    if backed == 0:
        print('      备份为空，中止（不做任何删除）。')
        return 1

    print(f'[2/4] 删除源表重复行（{SRC}）')
    cur.execute(f'DELETE FROM {SRC} WHERE {where}', date_params)
    src_deleted = cur.rowcount
    conn.commit()
    print(f'      已删除 {src_deleted:,} 行')

    print(f'[3/4] 清理 ODS 中的同一批行（{ODS}）')
    if table_exists(cur, ODS):
        cur.execute(f'DELETE FROM {ODS} WHERE {where}', date_params)
        ods_deleted = cur.rowcount
        conn.commit()
        note = '（ODS 尚无这些行，说明这批数据还没跑过 ETL）' if ods_deleted == 0 else ''
        print(f'      已删除 {ods_deleted:,} 行{note}')
    else:
        print('      跳过（ODS 表不存在）')

    print('[4/4] 清理后的每日行数')
    after = stats_by_day(cur, SRC, start, end, created_on)
    for d, (total, dupe) in after.items():
        print(f'  {d}  {before.get(d, (0, 0))[0]:>6} → {total:>6}   (残留标记 {dupe})')

    print('\n' + '=' * 64)
    print(f'完成：删除 {src_deleted:,} 行源表重复流水，备份在 {bak}')
    print(r'下一步：python scripts\etl_scheduler.py --once   # 重跑 ETL 让下游重算')
    print('=' * 64)
    cur.close()
    conn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
