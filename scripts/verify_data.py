#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
数仓数据校验（把文档里的「对答案」变成可执行断言）
====================================================
为什么要它：
    项目文档里有一堆"对答案"表格（各表行数、营收对账、预警类型数…），
    但每次重跑数据这些数字就会变旧，已经反复手工对齐过好几轮。
    本脚本把这些检查变成可执行断言，跑一次就知道数据对不对。

检查分三类：
    1) 规模   —— 各表非空，并打印真实行数 / 日期范围（供人肉比对文档）
    2) 对账   —— 同一指标跨层一致：DWD = DWS = ADS（营收、产量）
    3) 一致性 —— 预警 5 类齐全且主键唯一、库存健康单一基准日、大屏逐日无断层、维度无孤儿

用法：
    python scripts/verify_data.py            # 校验；全通过退出码 0，否则 1
    python scripts/verify_data.py --quiet    # 只输出失败项与结论

也被 etl_scheduler.py 在跑完 step05 后调用（见 run()）。
退出码：0 = 全部通过；1 = 有检查项失败
"""

import argparse
import os
import sys

import pymysql

# 对账容差：ADS 的值是逐行 ROUND(…,2) 后再汇总，会有极小舍入漂移，
# 用相对容差 0.1% 判定，避免把舍入误判成"不一致"。
TOL = 1e-3

# 表 → 日期列（None 表示该表没有自然日期列，只查行数）
TABLES = [
    ('ads_db.ads_boss_dashboard', 'stat_date'),
    ('ads_db.ads_sale_analysis', 'stat_date'),
    ('ads_db.ads_produce_monitor', 'stat_date'),
    ('ads_db.ads_stock_health', 'stat_date'),
    ('ads_db.ads_cost_profit', None),
    ('ads_db.ads_alert_warning', 'alert_date'),
    ('dwd_db.dim_date', 'date_key'),
]

# 事实表键 → 维度表键（用于"维度无孤儿"检查）
# 末位是"已知占位值"：上游把 NULL 脏数据映射成了这些值（如 step04 的
# COALESCE(customer_id,'UNKNOWN')），它们本来就查不到维度，不算孤儿。
ORPHAN_SPECS = [
    ('ads_db.ads_sale_analysis', 'customer_id', 'dwd_db.dim_customer', 'customer_id', ("UNKNOWN",)),
    ('ads_db.ads_produce_monitor', 'workshop_id', 'dwd_db.dim_workshop', 'workshop_id', ()),
    ('ads_db.ads_stock_health', 'material_id', 'dwd_db.dim_material', 'material_id', ()),
]


class Report:
    """收集检查结果；printer=None 时只收集不打印（给调度器写日志用）。"""

    def __init__(self, quiet=False, printer=print):
        self.quiet = quiet
        self.printer = printer
        self.items = []
        self.lines = []

    def out(self, s=''):
        self.lines.append(s)
        if self.printer:
            self.printer(s)

    def add(self, ok, label, detail=''):
        self.items.append((bool(ok), label, detail))
        if ok and self.quiet:
            return
        self.out('  %s %-24s %s' % ('✓' if ok else '✗', label, detail))

    def section(self, title):
        if not self.quiet:
            self.out('\n[%s]' % title)

    @property
    def failed(self):
        return [x for x in self.items if not x[0]]

    def finish(self):
        n, bad = len(self.items), len(self.failed)
        self.out('\n' + '=' * 62)
        if bad:
            self.out('结果：%d 项检查，%d 项失败' % (n, bad))
            for _, label, detail in self.failed:
                self.out('   ✗ %s %s' % (label, detail))
        else:
            self.out('结果：全部通过（%d 项检查）' % n)
        self.out('=' * 62)
        return not bad


def close_enough(a, b):
    a, b = float(a or 0), float(b or 0)
    if a == b:
        return True
    return abs(a - b) / max(abs(a), abs(b), 1.0) <= TOL


def comma(x):
    return '{:,}'.format(int(x or 0))


def run(quiet=False, printer=print):
    """
    执行全部校验。
    返回 (是否全部通过: bool, 输出行列表: list[str])
    """
    rep = Report(quiet=quiet, printer=printer)
    conn = pymysql.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=int(os.environ.get('DB_PORT', '3306')),
        user=os.environ.get('DB_USER', 'root'),
        password=os.environ.get('DB_PASSWORD', 'root'),
        charset='utf8mb4')
    cur = conn.cursor()

    def one(sql):
        cur.execute(sql)
        return cur.fetchone()

    def val(sql):
        row = one(sql)
        return row[0] if row else None

    def rows(sql):
        cur.execute(sql)
        return cur.fetchall()

    try:
        rep.out('制造数仓 · 数据校验')
        rep.out('=' * 62)

        # ---------------- 1. 规模 ----------------
        rep.section('各表规模（真实值，供与文档比对）')
        for tbl, date_col in TABLES:
            name = tbl.split('.')[-1]
            if date_col:
                cnt, dmin, dmax = one('SELECT COUNT(*), MIN(%s), MAX(%s) FROM %s'
                                      % (date_col, date_col, tbl))
                rep.add(cnt > 0, name, '%s 行   %s ~ %s' % (comma(cnt), dmin, dmax))
            else:
                cnt = val('SELECT COUNT(*) FROM ' + tbl)
                rep.add(cnt > 0, name, '%s 行' % comma(cnt))

        # ---------------- 2. 跨层对账 ----------------
        rep.section('跨层对账（DWD = DWS = ADS）')

        rev = {
            'DWD有效订单': val("SELECT SUM(order_amount) FROM dwd_db.dwd_sale_order_detail "
                               "WHERE order_status NOT IN ('已取消','已作废')"),
            'DWS日汇总': val('SELECT SUM(order_amt) FROM dws_db.dws_sale_day'),
            'DWS月汇总': val('SELECT SUM(order_amt) FROM dws_db.dws_sale_month'),
            'ADS销售分析': val('SELECT SUM(order_amt) FROM ads_db.ads_sale_analysis'),
            'ADS大屏': val('SELECT SUM(total_revenue) FROM ads_db.ads_boss_dashboard'),
        }
        base = rev['DWD有效订单']
        bad_rev = [k for k, v in rev.items() if not close_enough(v, base)]
        rep.add(not bad_rev, '营收对账',
                '%.4f 亿，4 层一致' % (float(base or 0) / 1e8) if not bad_rev
                else '不一致：' + ' / '.join('%s=%.2f' % (k, float(rev[k] or 0)) for k in rev))

        prod = {}
        for name, tbl in [('DWD', 'dwd_db.dwd_produce_workorder_detail'),
                          ('DWS', 'dws_db.dws_produce_day'),
                          ('ADS', 'ads_db.ads_produce_monitor')]:
            prod[name] = one('SELECT SUM(plan_qty), SUM(actual_qty), SUM(defect_qty) FROM ' + tbl)

        bad_prod = [(n, i) for n in ('DWS', 'ADS') for i in range(3)
                    if not close_enough(prod['DWD'][i], prod[n][i])]
        pq, aq, dq = prod['DWD']
        rep.add(not bad_prod, '产量对账',
                'plan %s / actual %s / defect %s（DWD=DWS=ADS）' % (comma(pq), comma(aq), comma(dq))
                if not bad_prod else '不一致：%s' % bad_prod)

        rep.add(True, '不良品占比',
                '不良 %s / 实际 %s = %.2f%%' % (comma(dq), comma(aq),
                                            (float(dq or 0) / float(aq or 1)) * 100))

        # ---------------- 3. 一致性 ----------------
        rep.section('一致性')

        types, cnt, ids = one('SELECT COUNT(DISTINCT alert_type), COUNT(*), COUNT(DISTINCT alert_id) '
                              'FROM ads_db.ads_alert_warning')
        rep.add(types == 5, '预警类型齐全', '%d 类 / %s 条' % (types, comma(cnt)))
        rep.add(ids == cnt, '预警主键唯一', 'distinct alert_id = %s，行数 = %s' % (comma(ids), comma(cnt)))

        levels = [x[0] for x in rows('SELECT DISTINCT alert_level FROM ads_db.ads_alert_warning')]
        rep.add(bool(levels) and set(levels) <= {'高', '中', '低'}, '预警等级合法',
                '、'.join(sorted(levels)) if levels else '（无）')

        days = val('SELECT COUNT(DISTINCT stat_date) FROM ads_db.ads_stock_health')
        n_rows = val('SELECT COUNT(*) FROM ads_db.ads_stock_health')
        mats = val('SELECT COUNT(DISTINCT material_id) FROM ads_db.ads_stock_health')
        whs = val('SELECT COUNT(DISTINCT warehouse_id) FROM ads_db.ads_stock_health')
        rep.add(days == 1, '库存健康单一基准日', '%d 个日期' % days)
        rep.add(n_rows == mats * whs, '库存健康无重复(物料×仓库)',
                '%s 行 = %d 物料 × %d 仓库' % (comma(n_rows), mats, whs))

        n_boss, dmin, dmax = one('SELECT COUNT(*), MIN(stat_date), MAX(stat_date) '
                                 'FROM ads_db.ads_boss_dashboard')
        span = val('SELECT DATEDIFF(MAX(stat_date), MIN(stat_date)) + 1 FROM ads_db.ads_boss_dashboard')
        rep.add(n_boss == span, '大屏逐日无断层', '%s 行，跨度 %s 天' % (comma(n_boss), span))

        months = val('SELECT COUNT(DISTINCT stat_month) FROM ads_db.ads_cost_profit')
        rep.add(months >= 1, '成本利润有月份数据', '%d 个月' % months)

        orphans, placeholders = [], []
        for fact, fcol, dim, dcol, ph in ORPHAN_SPECS:
            ph_sql = ''
            if ph:
                ph_sql = ' AND f.%s NOT IN (%s)' % (fcol, ','.join("'%s'" % x for x in ph))
            n = val('SELECT COUNT(*) FROM %s f LEFT JOIN %s d ON f.%s = d.%s '
                    'WHERE f.%s IS NOT NULL AND d.%s IS NULL%s'
                    % (fact, dim, fcol, dcol, fcol, dcol, ph_sql))
            if n:
                orphans.append('%s.%s 有 %s 条无关联' % (fact.split('.')[-1], fcol, comma(n)))
            if ph:
                m = val('SELECT COUNT(*) FROM %s WHERE %s IN (%s)'
                        % (fact, fcol, ','.join("'%s'" % x for x in ph)))
                placeholders.append('%s.%s=%s 共 %s 行'
                                    % (fact.split('.')[-1], fcol, '/'.join(ph), comma(m)))
        rep.add(not orphans, '维度无孤儿', '；'.join(orphans) if orphans else '全部可关联（已知占位值除外）')
        if placeholders:
            rep.add(True, '脏数据占位（按设计保留）', '；'.join(placeholders))

        return rep.finish(), rep.lines
    finally:
        cur.close()
        conn.close()


def main():
    ap = argparse.ArgumentParser(description='数仓数据校验')
    ap.add_argument('--quiet', action='store_true', help='只输出失败项与结论')
    args = ap.parse_args()
    ok, _ = run(quiet=args.quiet)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
