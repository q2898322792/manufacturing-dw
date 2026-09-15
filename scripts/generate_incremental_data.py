#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
增量业务数据生成脚本
功能：在现有数据基础上按天追加新数据，模拟真实业务持续发生。

覆盖的源表（原实现缺了成本凭证和库存快照，导致成本/库存看板永远不更新）：
    销售订单 erp_db.sale_order
    生产工单 mes_db.produce_workorder
    成本凭证 erp_db.cost_voucher          ← 新增
    出入库   wms_db.stock_io_detail
    库存快照 wms_db.stock_snapshot        ← 新增（按结存累加，不再空跑）
    设备运行 mes_db.equipment_runtime

运行方式：
    python generate_incremental_data.py                          # 只生成"今天"一天（配合每日调度）
    python generate_incremental_data.py 2026-07-01 2026-09-10    # 补齐区间，已有数据的日期自动跳过
"""

import os
import sys
import random
import datetime
import hashlib
from faker import Faker
import pymysql

# Windows 控制台编码兼容：GBK 控制台打印 emoji/中文不抛 UnicodeEncodeError
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

# ============================================================
# 一、全局配置
# ============================================================

DB_CONFIG = {
    'host': os.environ.get('DB_HOST', '127.0.0.1'),
    'port': int(os.environ.get('DB_PORT', '3306')),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', 'root'),   # 原实现写死占位符 '你的密码'，一跑就连接失败
    'charset': 'utf8mb4',
}

# 增量数据时间范围（默认只生成"今天"，可通过命令行参数指定区间做回补）
START_DATE = datetime.date.today()
END_DATE = datetime.date.today()

# 每天各表增量数据量；None = 从历史数据自动推算日均量
DAILY_SALE_ORDERS = None      # 原实现写死 50，而历史日均 3600+，导致增量日营收只有历史的 1/70
DAILY_WORKORDERS = None
DAILY_EQUIPMENT = 4           # 与设备台数一致

# 脏数据比例（增量数据也保持 0.5% 脏数据率）
DIRTY_RATIO = 0.005

# ============================================================
# 价格 / 成本 口径（与 generate_fake_data.py 保持一致：同一 ID 结果一致）
# ============================================================

UNIT_COST_MIN, UNIT_COST_MAX = 80.0, 600.0
MATERIAL_PRICE_MIN, MATERIAL_PRICE_MAX = 5.0, 800.0
MARGIN_MIN, MARGIN_MAX = 0.22, 0.34
COST_MIX = (0.60, 0.22, 0.18)
PLAN_QTY_MIN, PLAN_QTY_MAX = 20, 200
ORDER_QTY_MIN, ORDER_QTY_MAX = 10, 60
DELIVERY_SLA_DAYS = 7
WAREHOUSES = ['原材料仓', '半成品仓', '成品仓']


def _stable_ratio(key, salt=''):
    """把任意 ID 稳定映射到 [0,1)"""
    h = hashlib.md5(f"{salt}{key}".encode('utf-8')).hexdigest()
    return int(h[:8], 16) / 0xFFFFFFFF


def material_unit_price(material_id):
    return round(MATERIAL_PRICE_MIN + (MATERIAL_PRICE_MAX - MATERIAL_PRICE_MIN) * _stable_ratio(material_id, 'mat:'), 2)


def product_unit_cost(product_id):
    return round(UNIT_COST_MIN + (UNIT_COST_MAX - UNIT_COST_MIN) * _stable_ratio(product_id, 'cost:'), 2)


def product_gross_margin(product_id):
    return round(MARGIN_MIN + (MARGIN_MAX - MARGIN_MIN) * _stable_ratio(product_id, 'margin:'), 4)


def product_unit_price(product_id):
    return round(product_unit_cost(product_id) / (1 - product_gross_margin(product_id)), 2)


def split_cost(total_cost):
    weights = [mix * random.uniform(0.94, 1.06) for mix in COST_MIX]
    total_w = sum(weights)
    material_cost = round(total_cost * weights[0] / total_w, 2)
    labor_cost = round(total_cost * weights[1] / total_w, 2)
    mfg_cost = round(total_cost - material_cost - labor_cost, 2)
    return material_cost, labor_cost, mfg_cost


# ============================================================
# 二、初始化
# ============================================================

fake = Faker('zh_CN')
conn = pymysql.connect(**DB_CONFIG)
cursor = conn.cursor()


# ============================================================
# 三、获取现有 ID 池
# ============================================================

def load_id_pools():
    """从现有数据中加载所有维度表 ID"""
    cursor.execute("SELECT customer_id FROM erp_db.customer")
    customer_ids = [row[0] for row in cursor.fetchall()]

    cursor.execute("SELECT product_id FROM erp_db.product")
    product_ids = [row[0] for row in cursor.fetchall()]

    cursor.execute("SELECT material_id FROM erp_db.material")
    material_ids = [row[0] for row in cursor.fetchall()]

    cursor.execute("SELECT workshop_id FROM mes_db.workshop")
    workshop_ids = [row[0] for row in cursor.fetchall()]

    cursor.execute("SELECT supplier_id FROM wms_db.supplier")
    supplier_ids = [row[0] for row in cursor.fetchall()]

    return customer_ids, product_ids, material_ids, workshop_ids, supplier_ids


customer_ids, product_ids, material_ids, workshop_ids, supplier_ids = load_id_pools()

print(f"✅ 已加载维度数据：客户 {len(customer_ids)} 条，产品 {len(product_ids)} 条，"
      f"物料 {len(material_ids)} 条，车间 {len(workshop_ids)} 条")


def infer_daily_volume():
    """从历史数据推算日均增量，保证增量日的数据量与历史处在同一量级"""
    def avg(table, date_col):
        cursor.execute(f"SELECT COUNT(*), COUNT(DISTINCT {date_col}) FROM {table}")
        total, days = cursor.fetchone()
        return max(10, int((total or 0) / max(1, days or 1)))

    return {
        'sale': avg('erp_db.sale_order', 'order_date'),
        'workorder': avg('mes_db.produce_workorder', 'plan_start_date'),
    }


DAILY_VOLUME = infer_daily_volume()
if DAILY_SALE_ORDERS is None:
    DAILY_SALE_ORDERS = DAILY_VOLUME['sale']
if DAILY_WORKORDERS is None:
    DAILY_WORKORDERS = DAILY_VOLUME['workorder']
print(f"✅ 按历史日均推算增量规模：销售订单 {DAILY_SALE_ORDERS} 条/天，生产工单 {DAILY_WORKORDERS} 条/天")


# ============================================================
# 四、批量插入工具
# ============================================================

def batch_insert(sql, data_list, batch_size=2000):
    """批量插入（批大小从 1000 提到 2000，并减少逐条打印）"""
    for i in range(0, len(data_list), batch_size):
        batch = data_list[i:i + batch_size]
        cursor.executemany(sql, batch)
        conn.commit()
    print(f"  已插入 {len(data_list)} 条")


def date_has_data(target_date):
    """判断该日期是否已经生成过数据，避免回补时重复写入"""
    cursor.execute("SELECT COUNT(*) FROM erp_db.sale_order WHERE order_date = %s", (target_date,))
    return cursor.fetchone()[0] > 0


# ============================================================
# 五、增量数据生成函数
# ============================================================

def generate_incremental_sale_orders(target_date):
    """生成指定日期的增量销售订单（单价 = 产品标准售价，数量含季节波动）"""
    print(f"\n📋 生成 {target_date} 的销售订单...")
    sql = """
        INSERT INTO erp_db.sale_order 
        (order_id, customer_id, product_id, order_date, order_amount, 
         tax_amount, discount_amount, net_amount, order_status, 
         delivery_date, payment_date, region, quantity, create_time, update_time)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    regions = ['华东', '华南', '华北', '西南', '西北', '华中', '东北']

    month = target_date.month
    if month in (12, 1):
        season_factor = random.uniform(1.5, 2.5)
    elif month in (6, 7):
        season_factor = random.uniform(1.3, 2.0)
    elif month == 2:
        season_factor = random.uniform(0.3, 0.7)
    else:
        season_factor = random.uniform(0.7, 1.3)

    for _ in range(DAILY_SALE_ORDERS):
        customer_id = random.choice(customer_ids) if random.random() > DIRTY_RATIO / 2 else None
        product_id = random.choice(product_ids) if random.random() > DIRTY_RATIO / 2 else 'INVALID_001'

        quantity = max(1, int(random.randint(ORDER_QTY_MIN, ORDER_QTY_MAX)
                              * season_factor * random.uniform(0.85, 1.15)))
        price = product_unit_price(product_id) * random.uniform(0.98, 1.02)
        amount = round(price * quantity, 2)
        tax = round(amount * 0.13, 2)
        discount = round(amount * random.uniform(0, 0.15), 2) if random.random() > 0.3 else 0
        net = round(amount + tax - discount, 2)

        if random.random() < DIRTY_RATIO:
            amount = random.choice([-999, 99999999, 0])
            tax = 0
            net = amount

        # 状态与交付/回款（口径与历史数据一致）
        roll = random.random()
        if roll < 0.10:
            status, delivery_date, payment_date = '已取消', None, None
        elif roll < 0.12:
            status, delivery_date, payment_date = '已作废', None, None
        elif roll < 0.20:
            status, delivery_date, payment_date = '已提交', None, None
        else:
            if random.random() < 0.88:
                delivery_date = target_date + datetime.timedelta(days=random.randint(1, DELIVERY_SLA_DAYS))
            else:
                delivery_date = target_date + datetime.timedelta(days=random.randint(DELIVERY_SLA_DAYS + 1, 40))
            if random.random() < 0.03:      # 3% 交付后退货（退货金额进 return_amt）
                status, payment_date = '已退货', None
            else:
                status = '已完成' if random.random() < 0.7 else '已发货'
                payment_date = (delivery_date + datetime.timedelta(days=random.randint(0, 40))
                                if random.random() < 0.8 else None)

        now = datetime.datetime.now()
        data.append((
            fake.uuid4().replace('-', '')[:32],
            customer_id, product_id,
            target_date,
            amount, tax, discount, net,
            status,
            delivery_date, payment_date,
            random.choice(regions),
            quantity,
            now, now
        ))

    batch_insert(sql, data)
    print(f"  ✅ 销售订单增量完成：{len(data)} 条")


def generate_incremental_workorders(target_date):
    """生成指定日期的增量生产工单，返回当天的工单明细（供成本凭证使用）"""
    print(f"\n📋 生成 {target_date} 的生产工单...")
    sql = """
        INSERT INTO mes_db.produce_workorder 
        (workorder_id, product_id, workshop_id, plan_qty, actual_qty, 
         qualified_qty, defect_qty, defect_type, plan_start_date, plan_end_date, 
         actual_start_date, actual_end_date, workorder_status, labor_hours, 
         material_loss, create_time, update_time)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    created = []
    defect_types = ['尺寸偏差', '外观缺陷', '性能失效', '其他']

    for _ in range(DAILY_WORKORDERS):
        product_id = random.choice(product_ids)
        plan_qty = random.randint(PLAN_QTY_MIN, PLAN_QTY_MAX)

        # 先定产量，再算良品/不良，保证 良品 + 不良 = 实际产量 恒成立
        if random.random() < DIRTY_RATIO:
            actual_qty = plan_qty * 10
            qualified_rate = random.uniform(50, 70)
        else:
            actual_qty = int(plan_qty * random.uniform(0.6, 1.0))
            qualified_rate = random.uniform(0.85, 1.0)

        qualified = int(actual_qty * qualified_rate) if actual_qty > 0 else 0
        defect = actual_qty - qualified if actual_qty > 0 else 0

        labor_hours = round(actual_qty * random.uniform(0.03, 0.08), 2)
        material_loss = round(actual_qty * product_unit_cost(product_id) * random.uniform(0.005, 0.02), 2)

        plan_end = target_date + datetime.timedelta(days=random.randint(1, 30))
        status = random.choice(['未开工', '生产中', '已完工', '已关闭', '已逾期'])

        now = datetime.datetime.now()
        workorder_id = fake.uuid4().replace('-', '')[:32]
        workshop_id = random.choice(workshop_ids)
        data.append((
            workorder_id,
            product_id, workshop_id,
            plan_qty, max(0, actual_qty), max(0, qualified), max(0, defect),
            random.choice(defect_types) if defect > 0 else None,
            target_date, plan_end,
            target_date + datetime.timedelta(days=random.randint(1, 5)) if status in ['生产中', '已完工'] else None,
            target_date + datetime.timedelta(days=random.randint(1, 20)) if status in ['已完工', '已关闭'] else None,
            status,
            labor_hours,
            material_loss,
            now, now
        ))
        created.append((workorder_id, product_id, workshop_id, max(0, actual_qty)))

    batch_insert(sql, data)
    print(f"  ✅ 生产工单增量完成：{len(data)} 条")
    return created


def generate_incremental_cost_voucher(target_date, workorders):
    """生成指定日期的增量成本凭证（成本 = 产品单位成本 × 实际产量）

    原实现完全没有这一步，导致成本利润看板的数据永远停在初始区间。
    """
    print(f"\n📋 生成 {target_date} 的成本凭证...")
    sql = """
        INSERT INTO erp_db.cost_voucher 
        (voucher_id, product_id, workshop_id, workorder_id, material_cost, labor_cost, mfg_cost, total_cost, cost_month)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    cost_month = target_date.strftime('%Y-%m')

    for _workorder_id, product_id, workshop_id, actual_qty in workorders:
        total_cost = round(product_unit_cost(product_id) * actual_qty * random.uniform(0.96, 1.04), 2)
        if total_cost <= 0:
            continue
        material_cost, labor_cost, mfg_cost = split_cost(total_cost)
        data.append((
            fake.uuid4().replace('-', '')[:32],
            product_id,
            workshop_id,
            _workorder_id,
            material_cost,
            labor_cost,
            mfg_cost,
            total_cost,
            cost_month
        ))

    if not data:
        print("  ⚠️ 当天没有可用工单，跳过成本凭证")
        return

    batch_insert(sql, data)
    print(f"  ✅ 成本凭证增量完成：{len(data)} 条")


def generate_incremental_stock(target_date):
    """生成指定日期的出入库明细 + 库存日快照（快照 = 上一日结存 + 当日入库 - 当日出库）

    原实现只生成出入库流水，不生成快照，导致库存看板永远停在初始区间；
    而且出入库是纯随机数，与结存无关，周转天数没有业务含义。
    """
    print(f"\n📋 生成 {target_date} 的出入库 + 库存快照...")
    io_sql = """
        INSERT INTO wms_db.stock_io_detail 
        (io_id, material_id, warehouse_id, io_type, io_qty, io_amount, 
         unit_price, io_date, supplier_id, workorder_id, order_id, create_time, update_time)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    snap_sql = """
        INSERT INTO wms_db.stock_snapshot 
        (snapshot_id, material_id, warehouse_id, snapshot_date, stock_qty, stock_amount, create_time, update_time)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """

    # 取 target_date 之前最近一天的快照作为期初结存
    cursor.execute("""
        SELECT s.material_id, s.warehouse_id, s.stock_qty
        FROM wms_db.stock_snapshot s
        WHERE s.snapshot_date = (
            SELECT MAX(snapshot_date) FROM wms_db.stock_snapshot WHERE snapshot_date < %s
        )
    """, (target_date,))
    opening = {(m, w): q for m, w, q in cursor.fetchall()}

    # 取当天已存在的工单/订单，用于把出入库挂到业务单据上
    cursor.execute("SELECT workorder_id FROM mes_db.produce_workorder WHERE plan_start_date = %s", (target_date,))
    today_workorders = [r[0] for r in cursor.fetchall()]
    cursor.execute("SELECT order_id FROM erp_db.sale_order WHERE order_date = %s", (target_date,))
    today_orders = [r[0] for r in cursor.fetchall()]

    io_rows, snap_rows = [], []
    now = datetime.datetime.now()

    for material_id in material_ids:
        for warehouse_id in WAREHOUSES:
            key = (material_id, warehouse_id)
            # 没有历史结存的组合给一个期初库存
            qty_on_hand = opening.get(key, random.randint(50, 800))
            price = material_unit_price(material_id)

            for _ in range(random.randint(1, 4)):
                if random.random() < 0.5:
                    qty = random.randint(10, 300)
                    qty_on_hand += qty
                    io_type = 'IN'
                    supplier_id = random.choice(supplier_ids) if random.random() > 0.5 else None
                    workorder_id, order_id = None, None
                else:
                    qty = min(random.randint(10, 300), qty_on_hand)
                    if qty <= 0:
                        continue
                    qty_on_hand -= qty
                    io_type = 'OUT'
                    supplier_id = None
                    workorder_id = random.choice(today_workorders) if today_workorders and random.random() > 0.5 else None
                    order_id = random.choice(today_orders) if today_orders and random.random() > 0.3 else None

                amount = round(qty * price, 2)
                if random.random() < DIRTY_RATIO:
                    amount = -9999

                io_rows.append((
                    fake.uuid4().replace('-', '')[:32],
                    material_id, warehouse_id, io_type, qty, amount, price,
                    target_date, supplier_id, workorder_id, order_id, now, now
                ))

            snap_rows.append((
                fake.uuid4().replace('-', '')[:32],
                material_id, warehouse_id, target_date,
                qty_on_hand, round(qty_on_hand * price, 2), now, now
            ))

    batch_insert(io_sql, io_rows)
    batch_insert(snap_sql, snap_rows)
    print(f"  ✅ 出入库 {len(io_rows)} 条，库存快照 {len(snap_rows)} 条")


def generate_incremental_equipment(target_date):
    """生成指定日期的增量设备运行记录"""
    print(f"\n📋 生成 {target_date} 的设备运行记录...")
    sql = """
        INSERT INTO mes_db.equipment_runtime 
        (record_id, equipment_id, workshop_id, record_date, runtime_min, 
         idle_min, fault_min, maintain_min, total_min, create_time, update_time)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    equipment_names = ['设备A-001', '设备A-002', '设备B-001', '设备C-001']

    for eq_name in equipment_names[:DAILY_EQUIPMENT]:
        # 四项时间之和恒等于 1440 分钟，OEE = 运行时间 / 1440 才有意义
        fault = random.randint(0, 120) if random.random() > 0.7 else 0
        maintain = random.randint(0, 90) if random.random() > 0.5 else 0
        idle = random.randint(60, 300)
        runtime = max(0, 1440 - idle - fault - maintain)
        total = runtime + idle + fault + maintain

        now = datetime.datetime.now()
        data.append((
            fake.uuid4().replace('-', '')[:32],
            eq_name,
            random.choice(workshop_ids),
            target_date,
            runtime, idle, fault, maintain,
            total,
            now, now
        ))

    batch_insert(sql, data)
    print(f"  ✅ 设备运行增量完成：{len(data)} 条")


# ============================================================
# 六、主程序
# ============================================================

def generate_incremental_data(start_date, end_date):
    """按天生成增量数据（已有数据的日期自动跳过，支持区间回补）"""
    total_days = (end_date - start_date).days + 1
    print("=" * 60)
    print(f"🚀 开始生成增量数据")
    print(f"📅 时间范围: {start_date} ~ {end_date} ({total_days} 天)")
    print(f"📊 每天约 {DAILY_SALE_ORDERS + DAILY_WORKORDERS + len(material_ids) * len(WAREHOUSES) * 2} 条数据")
    print("=" * 60)

    skipped, done = 0, 0
    current_date = start_date
    while current_date <= end_date:
        if date_has_data(current_date):
            print(f"\n⏭️  {current_date} 已有数据，跳过（避免重复累加）")
            skipped += 1
            current_date += datetime.timedelta(days=1)
            continue

        print(f"\n{'=' * 60}")
        print(f"📅 正在处理: {current_date}")
        print("=" * 60)

        try:
            generate_incremental_sale_orders(current_date)
            today_workorders = generate_incremental_workorders(current_date)
            generate_incremental_cost_voucher(current_date, today_workorders)
            generate_incremental_stock(current_date)
            generate_incremental_equipment(current_date)

            conn.commit()
            done += 1
            print(f"✅ {current_date} 增量数据生成完成")

        except Exception as e:
            print(f"❌ {current_date} 生成失败: {e}")
            conn.rollback()

        current_date += datetime.timedelta(days=1)

    print("\n" + "=" * 60)
    print(f"🎉 增量数据生成完成！成功 {done} 天，跳过 {skipped} 天")
    print("=" * 60)


# ============================================================
# 七、入口
# ============================================================

if __name__ == "__main__":
    # 支持命令行指定日期区间：python generate_incremental_data.py 2026-07-01 2026-09-10
    if len(sys.argv) >= 3:
        START_DATE = datetime.datetime.strptime(sys.argv[1], '%Y-%m-%d').date()
        END_DATE = datetime.datetime.strptime(sys.argv[2], '%Y-%m-%d').date()

    try:
        generate_incremental_data(START_DATE, END_DATE)
    except Exception as e:
        print(f"❌ 执行失败: {e}")
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()
