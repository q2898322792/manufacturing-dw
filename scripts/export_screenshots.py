#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FineBI 看板截图导出工具（bl/*.pdf → docs/screenshots/*.png）
====================================================
背景：
    FineBI 6.0 的**仪表板级导出只有「导出Excel」和「导出Pdf」两个选项，没有导出图片**。
    而 README 里要内联显示看板效果，必须是位图（PNG/JPEG）——PDF 在 Markdown 里无法内联。

    于是走这条路：FineBI 导出 PDF → 本脚本把 PDF 转成规格统一的 PNG。

为什么转换是无损的：
    实测 FineBI 导出的 PDF 内部**不是矢量图，而是把整个仪表板渲染成一张
    8175×4020 的位图**再塞进 PDF（每个 PDF 1 页、内嵌 1 张图）。
    所以"转 PNG"只是把这张大图按目标宽度等比缩小，不存在矢量转位图的失真问题。

为什么要控制尺寸：
    仓库里曾有一批 12429×6045 级别的整页截图被 git add 进仓库，
    二进制对象不可增量存储，直接导致 .git 膨胀到 57 MB（见 docs/PROJECT_MEMORY.md §7.5）。
    README 里 GitHub 正文栏宽度约 880 px，1600 px 宽足够在 HiDPI 屏上清晰显示，
    单张控制在 500 KB 以内。

用法：
    python scripts/export_screenshots.py                  # 默认：bl/*.pdf → docs/screenshots/，宽 1600
    python scripts/export_screenshots.py --width 1400     # 改目标宽度
    python scripts/export_screenshots.py --out _shot_test # 输出到临时目录试跑
    python scripts/export_screenshots.py --dry-run        # 只列出映射关系，不写文件
"""

import argparse
import os
import re
import sys

try:
    import pymupdf
except ImportError:          # 旧版本包名
    import fitz as pymupdf

# PDF 文件名（不含扩展名）→ 输出文件名（英文+序号，避免 Windows 命令行下的中文乱码）
NAME_MAP = {
    '经营总览大屏': '01-boss-dashboard',
    '销售分析': '02-sale-analysis',
    '生产监控': '03-produce-monitor',
    '生产四象限': '04-produce-quadrant',
    '库存健康': '05-stock-health',
    '成本利润分析': '06-cost-profit',
    '异常预警清单': '07-alert-warning',
}

DEFAULT_SRC = 'bl'
DEFAULT_OUT = os.path.join('docs', 'screenshots')
DEFAULT_WIDTH = 1600
MAX_KB = 500


def slugify(name):
    """未在映射表里的文件名 → 安全输出名"""
    s = re.sub(r'[^\w\u4e00-\u9fff-]+', '-', name).strip('-')
    return s


def _content_bbox(png_path):
    """找出 PNG 的内容边界（返回裁剪框），没装 Pillow 时返回 None

    做法：以左上角像素为页面背景色，找出所有"与背景色差异 > 阈值"的像素的外接矩形。
    不能用"亮度 < 250"这种绝对阈值 —— 页面背景本身就是浅灰（约 245），
    会把整页都判成内容，裁不掉空白。
    阈值取 8：实测 3/8/20 三个阈值算出的边界几乎一致，说明内容边界很清晰、
    调阈值不会误裁内容。
    """
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return None
    im = Image.open(png_path).convert('RGB')
    bg = Image.new('RGB', im.size, im.getpixel((0, 0)))
    diff = ImageChops.difference(im, bg).convert('L')
    bbox = diff.point(lambda v: 255 if v > 8 else 0).getbbox()
    if not bbox:
        return None
    pad = max(6, round(im.width * 0.008))
    box = (max(0, bbox[0] - pad), max(0, bbox[1] - pad),
           min(im.width, bbox[2] + pad), min(im.height, bbox[3] + pad))
    if box[2] - box[0] < 100 or box[3] - box[1] < 100:
        return None
    return box


def convert(pdf_path, out_path, width, trim=True):
    """把 PDF 第 1 页按目标宽度渲染成 PNG，返回 (png宽, png高, 字节数)

    trim=True 时自动裁掉四周的纯色空白 —— FineBI 导出的页面里仪表板只占上半部分，
    实测 1600×848 里有 357 px（42%）是空的，直接放进 README 会显得很脏。
    """
    doc = pymupdf.open(pdf_path)
    if doc.page_count != 1:
        print('       ⚠️ 该 PDF 有 %d 页，只处理第 1 页' % doc.page_count)
    page = doc[0]
    zoom = width / page.rect.width
    pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    pix.save(out_path)
    w, h = pix.width, pix.height
    doc.close()

    if trim:
        box = _content_bbox(out_path)
        if box:
            try:
                from PIL import Image
                im = Image.open(out_path).crop(box)
                im.save(out_path)
                w, h = im.size
            except ImportError:
                pass
    return w, h, os.path.getsize(out_path)


def unify_width(paths):
    """把所有 PNG 补到同一宽度（居中，用各自背景色填充）

    为什么这么做：各看板内容宽度天然不同（实测裁边后 837 ~ 1434 px），
    放进 README 并排/顺序展示时宽窄不一，观感很乱。
    这里**不缩放**、只做居中补边 —— 缩放会把窄图放大变糊，
    而这些截图的可读性全靠 1:1 的原始分辨率。
    """
    try:
        from PIL import Image
    except ImportError:
        return None
    sizes = {}
    for p in paths:
        sizes[p] = Image.open(p).size
    target = max(w for w, _ in sizes.values())
    changed = 0
    for p, (w, h) in sizes.items():
        if w >= target:
            continue
        im = Image.open(p).convert('RGB')
        bg = im.getpixel((0, 0))
        canvas = Image.new('RGB', (target, h), bg)
        canvas.paste(im, ((target - w) // 2, 0))
        canvas.save(p)
        changed += 1
    return target, changed


def main():
    ap = argparse.ArgumentParser(description='把 FineBI 导出的看板 PDF 转成 README 用的 PNG')
    ap.add_argument('--src', default=DEFAULT_SRC, help='PDF 目录，默认 bl')
    ap.add_argument('--out', default=DEFAULT_OUT, help='PNG 输出目录，默认 docs/screenshots')
    ap.add_argument('--width', type=int, default=DEFAULT_WIDTH, help='目标宽度 px，默认 1600')
    ap.add_argument('--no-trim', action='store_true', help='不自动裁掉四周空白（默认会裁）')
    ap.add_argument('--no-unify', action='store_true', help='不统一输出宽度（默认会补边到同宽）')
    ap.add_argument('--dry-run', action='store_true', help='只列映射，不写文件')
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src_dir = os.path.join(root, args.src)
    out_dir = os.path.join(root, args.out)

    if not os.path.isdir(src_dir):
        print('❌ 源目录不存在：%s' % src_dir)
        return 1

    pdfs = sorted(f for f in os.listdir(src_dir) if f.lower().endswith('.pdf'))
    if not pdfs:
        print('❌ %s 下没有 PDF。先在 FineBI 里逐个看板「导出 → 导出Pdf」。' % src_dir)
        return 1

    print('=' * 64)
    print('FineBI 看板 PDF → PNG')
    print('  源目录  : %s' % args.src)
    print('  输出目录: %s' % args.out)
    print('  目标宽度: %d px' % args.width)
    print('  模式    : %s' % ('预览（dry-run）' if args.dry_run else '转换'))
    print('=' * 64)

    total = 0
    warn = []
    made = []
    for fn in pdfs:
        stem = os.path.splitext(fn)[0]
        out_name = NAME_MAP.get(stem, slugify(stem)) + '.png'
        out_path = os.path.join(out_dir, out_name)

        if args.dry_run:
            print('  %-22s → %s' % (stem + '.pdf', out_name))
            continue

        try:
            w, h, size = convert(os.path.join(src_dir, fn), out_path,
                                 args.width, trim=not args.no_trim)
        except Exception as e:
            print('  ❌ %-20s 转换失败: %s' % (stem, e))
            warn.append(stem)
            continue

        made.append(out_path)
        kb = size / 1024
        total += size
        flag = ''
        if kb > MAX_KB:
            flag = '  ⚠️ 超过 %d KB，可调小 --width' % MAX_KB
        print('  ✅ %-20s → %-28s %5dx%-5d %7.1f KB%s' % (stem, out_name, w, h, kb, flag))

    if not args.dry_run:
        if made and not args.no_unify:
            res = unify_width(made)
            if res:
                target, changed = res
                print('-' * 64)
                print('  统一宽度 → %d px（%d 张做了居中补边，未缩放、不损清晰度）'
                      % (target, changed))
        print('-' * 64)
        print('  合计 %.0f KB（%d 张）' % (total / 1024, len(pdfs) - len(warn)))
        if warn:
            print('  失败：%s' % '、'.join(warn))
        print('\n下一步：把 PNG 提交进仓库，并在 README.md 里内联引用（相对路径）。')
    return 0 if not warn else 1


if __name__ == '__main__':
    sys.exit(main())
