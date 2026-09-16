#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
四象限图「离线重绘」工具
====================================================
用途：不开 Jupyter 也能把 notebook《02_capacity_quality_analysis》里的
      「产能 × 良率」四象限图重新渲染成 PNG。

原理：直接从 notebook 里**取出绘图 cell 的源码**执行（不复制代码），
      因此产出永远与 notebook 当前代码一致，不会出现两处逻辑漂移。

用法：
    python scripts/render_quadrant_chart.py
    产物：notebooks/bi/analysis/capacity_quality_quadrant.png

注意：取数口径与 notebook 保持一致 —— ads_produce_monitor 按车间取均值。
"""

import os
import sys
import json

import pymysql
import pandas as pd
import matplotlib
matplotlib.use('Agg')                      # 无窗口环境（终端/CI）必须用 Agg
import matplotlib.pyplot as plt

# 字体必须与 notebook 第 1 个 cell 保持一致：
# 若这里换成 Microsoft YaHei 之类字形更全的字体，会把 notebook 里
# “字体缺字形导致显示成方框”的问题掩盖掉，失去离线预览的意义。
plt.rcParams['font.sans-serif'] = ['SimHei', 'Arial Unicode MS', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

CAP_STD, QUAL_STD = 80.0, 95.0
NB_REL = os.path.join('notebooks', '02_capacity_quality_analysis.ipynb')
CELL_ID = '7b5c7023'                       # 「第 5 段：可视化」cell
OUT_REL = 'bi/analysis/capacity_quality_quadrant.png'   # 相对 notebooks/


def classify_quadrant(row):
    cap_ok = row['capacity_achieved'] >= CAP_STD
    qual_ok = row['qualified_rate'] >= QUAL_STD
    if cap_ok and qual_ok:
        return '双优'
    if cap_ok and not qual_ok:
        return '高产低质'
    if not cap_ok and qual_ok:
        return '低产高质'
    return '双低'


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    # ---- 1. 取数，复现 notebook 的 df / ws ----
    conn = pymysql.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=int(os.environ.get('DB_PORT', '3306')),
        user=os.environ.get('DB_USER', 'root'),
        password=os.environ.get('DB_PASSWORD', 'root'),
        charset='utf8mb4')
    df = pd.read_sql('SELECT stat_date, workshop_name, capacity_achieved, qualified_rate '
                     'FROM ads_db.ads_produce_monitor', conn)
    conn.close()

    ws = df.groupby('workshop_name')[['capacity_achieved', 'qualified_rate']].mean().round(2)
    ws['产能距标准'] = (ws['capacity_achieved'] - CAP_STD).round(2)
    ws['良率距标准'] = (ws['qualified_rate'] - QUAL_STD).round(2)
    ws['象限'] = ws.apply(classify_quadrant, axis=1)
    print('车间数 %d：%s' % (len(ws), '、'.join(ws.index)))

    # ---- 2. 从 notebook 取绘图源码 ----
    with open(NB_REL, encoding='utf-8') as f:
        nb = json.load(f)
    cell = next((c for c in nb['cells'] if c.get('id') == CELL_ID), None)
    if cell is None:
        print('未找到绘图 cell（id=%s），notebook 可能被改过' % CELL_ID)
        return 1
    code = ''.join(cell['source'])

    # ---- 3. 在 notebooks/ 下执行（cell 里是相对路径）----
    os.chdir('notebooks')
    exec(compile(code, 'notebook_cell', 'exec'), {'ws': ws, 'plt': plt, 'pd': pd})
    print('已生成：%s' % os.path.abspath(OUT_REL))
    return 0


if __name__ == '__main__':
    sys.exit(main())
