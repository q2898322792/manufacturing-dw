#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
00_init_all.sql 生成器
====================================================
作用：把 sql/01~05 各层的建表脚本，拼成一份「一键初始化」脚本
      sql/00_init_all.sql（建 7 个库 + 全部表）。

为什么要有它：
    sql/01~05 里的分层 DDL 才是**唯一数据源**；00_init_all.sql 只是产物。
    改了分层 DDL 后跑一下本脚本重新生成即可，避免两者悄悄漂移
    （--check 模式可用来检查是否忘了同步）。

用法：
    python scripts/build_init_sql.py            # 生成 / 更新 sql/00_init_all.sql
    python scripts/build_init_sql.py --check    # 只校验是否同步；不同步则退出码 1
    python scripts/build_init_sql.py --out x.sql

换行符说明：
    内部统一按 LF 比较与写出。Windows 上 git 常配 core.autocrlf=true（工作区
    是 CRLF、仓库是 LF），本脚本会先把两边都归一化成 LF 再比，
    因此不会因 CRLF/LF 差异误报“不同步”。
"""

import argparse
import io
import os
import sys

# 层目录 → 数据库名（列表顺序 = 生成脚本里的执行顺序）
LAYERS = [
    ('sql/01_source_ddl/erp_db', 'erp_db'),
    ('sql/01_source_ddl/mes_db', 'mes_db'),
    ('sql/01_source_ddl/wms_db', 'wms_db'),
    ('sql/02_ods_db', 'ods_db'),
    ('sql/03_dwd_db', 'dwd_db'),
    ('sql/04_dws_db', 'dws_db'),
    ('sql/05_ads_db', 'ads_db'),
]
DATABASES = ['erp_db', 'mes_db', 'wms_db', 'ods_db', 'dwd_db', 'dws_db', 'ads_db']
DEFAULT_OUT = 'sql/00_init_all.sql'


def read_text(path):
    """读文本并统一成 LF 换行。"""
    with io.open(path, encoding='utf-8') as f:
        return f.read().replace('\r\n', '\n').replace('\r', '\n')


def build(root):
    """拼装初始化脚本。返回 (内容, [(库名, 表数), ...])。"""
    out = [
        '-- ============================================================',
        '-- 00_init_all.sql —— 一次性初始化：建 7 个库 + 全部分层表',
        '-- 用法：mysql -uroot -p < 00_init_all.sql',
        '-- 幂等：CREATE DATABASE IF NOT EXISTS / DROP TABLE IF EXISTS 均可重复执行',
        '-- 说明：dim_date 只建空表，数据由 step02 按实际日期动态重建',
        '--',
        '-- ⚠️ 本文件由 scripts/build_init_sql.py 自动生成，请勿手改；',
        '--    改了 sql/01~05 里的建表脚本后，跑一下该脚本重新生成。',
        '-- ============================================================',
        '',
        'SET NAMES utf8mb4;',
        '',
    ]
    for db in DATABASES:
        out.append('CREATE DATABASE IF NOT EXISTS %s '
                   'DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;' % db)
    out.append('')

    stats = []
    for rel_dir, db in LAYERS:
        src_dir = os.path.join(root, rel_dir)
        files = sorted(fn for fn in os.listdir(src_dir) if fn.endswith('.sql'))
        out.append('-- ============================================================')
        out.append('-- %s（%d 张表）' % (db, len(files)))
        out.append('-- ============================================================')
        out.append('USE %s;' % db)
        out.append('')
        for fn in files:
            out.append('-- ---------- %s ----------' % fn)
            out.append(read_text(os.path.join(src_dir, fn)).strip())
            out.append('')
        stats.append((db, len(files)))

    return '\n'.join(out) + '\n', stats


def main():
    ap = argparse.ArgumentParser(description='生成 / 校验 sql/00_init_all.sql')
    ap.add_argument('--check', action='store_true',
                    help='只校验是否与各层 DDL 同步，不写盘（不同步退出码 1）')
    ap.add_argument('--out', default=None, help='输出路径，默认 sql/00_init_all.sql')
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_path = args.out or DEFAULT_OUT
    if not os.path.isabs(out_path):
        out_path = os.path.join(root, out_path)
    rel_out = os.path.relpath(out_path, root)

    content, stats = build(root)
    total = sum(n for _, n in stats)

    # ---- 校验模式：只比内容，不写盘 ----
    if args.check:
        if not os.path.exists(out_path):
            print('[不同步] %s 不存在，请运行：python scripts/build_init_sql.py' % rel_out)
            return 1
        old = read_text(out_path)
        if old == content:
            print('[同步] %s 与各层 DDL 一致（%d 张表）' % (rel_out, total))
            return 0
        old_l, new_l = old.splitlines(), content.splitlines()
        diff = sum(1 for a, b in zip(old_l, new_l) if a != b) + abs(len(old_l) - len(new_l))
        print('[不同步] %s 与各层 DDL 不一致（约 %d 行差异）' % (rel_out, diff))
        print('         请运行：python scripts/build_init_sql.py')
        return 1

    # ---- 生成模式 ----
    with io.open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)
    print('已生成 %s' % rel_out)
    for db, n in stats:
        print('  %-8s %2d 张表' % (db, n))
    print('  合计 %d 张表' % total)
    return 0


if __name__ == '__main__':
    sys.exit(main())
