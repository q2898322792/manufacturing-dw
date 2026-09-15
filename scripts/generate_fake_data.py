#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
制造企业经营分析数据仓库 - 仿真数据生成脚本（150万行·波动版）
功能：向 erp_db / mes_db / wms_db 三套源库 11 张表注入测试数据
数据量：维度表 150-300 条，事实表 35-50 万条，总计约 150 万行
脏数据比例：≤ 1%
特点：引入季节因子、长期趋势、车间差异化、帕累托分布
"""

import random
import datetime
import hashlib
import sys
from faker import Faker
import pymysql

# ============================================================
# 一、全局配置
# ============================================================

# 数据库连接配置
DB_CONFIG = {
    'host': '127.0.0.1',
    'port': 3306,
    'user': 'root',
    'password': 'root',  # ⚠️ 改成你自己的 MySQL 密码
    'charset': 'utf8mb4'
}

# 时间范围配置（所有日期生成统一使用这些常量）
START_DATE = datetime.date(2025, 10, 1)
END_DATE = datetime.date(2026, 6, 30)
SNAPSHOT_START = datetime.date(2025, 9, 1)
SNAPSHOT_END = datetime.date(2026, 7, 31)

# 脏数据比例（严格控制 ≤ 1%）
DIRTY_RATIO = 0.005

# ============================================================
# 价格 / 成本 / 产量 口径（保证三者自洽，避免"成本与产量脱钩"）
# ============================================================
# 修正背景：原实现里"每张成本凭证的成本"是 uniform(100,5000) 随机数，与实际产量无关，
#           售价也是独立的 uniform(500,2000)，导致
#             ① 单位成本 ≈ 5.44 元/件、售价 ≈ 37.72 元/件 → 毛利率虚高到 85%；
#             ② 产量(3.97亿件) 是销量(4309万件) 的 9.2 倍 → 总成本反而大于总营收。
# 现在改为：单位成本按产品确定性生成 → 售价 = 单位成本/(1-目标毛利率) → 工单成本 = 单位成本 × 实际产量。
UNIT_COST_MIN, UNIT_COST_MAX = 80.0, 600.0   # 产品单位成本区间（元/件）
MATERIAL_PRICE_MIN, MATERIAL_PRICE_MAX = 5.0, 800.0  # 物料单价区间（元/件）
MARGIN_MIN, MARGIN_MAX = 0.22, 0.34          # 目标毛利率区间
COST_MIX = (0.60, 0.22, 0.18)                # 成本结构：物料 / 人工 / 制造费用
PLAN_QTY_MIN, PLAN_QTY_MAX = 20, 200         # 工单计划产量区间（配合"产量 ≈ 销量 × 1.1"）
ORDER_QTY_MIN, ORDER_QTY_MAX = 10, 60        # 订单基础数量区间
DELIVERY_SLA_DAYS = 7                        # 按时交付天数门槛（与 ETL 中口径保持一致）

# 是否在生成前清空 11 张源表（保证可重复生成、不重复累加）；命令行加 --append 可关闭
RESET_BEFORE_GENERATE = True


def _stable_ratio(key, salt=''):
    """把任意 ID 稳定映射到 [0,1)，保证同一 ID 每次运行结果一致（跨脚本也一致）"""
    h = hashlib.md5(f"{salt}{key}".encode('utf-8')).hexdigest()
    return int(h[:8], 16) / 0xFFFFFFFF


def material_unit_price(material_id):
    """物料标准单价（元/件）"""
    return round(MATERIAL_PRICE_MIN + (MATERIAL_PRICE_MAX - MATERIAL_PRICE_MIN) * _stable_ratio(material_id, 'mat:'), 2)


def product_unit_cost(product_id):
    """产品标准单位成本（元/件）"""
    return round(UNIT_COST_MIN + (UNIT_COST_MAX - UNIT_COST_MIN) * _stable_ratio(product_id, 'cost:'), 2)


def product_gross_margin(product_id):
    """产品目标毛利率"""
    return round(MARGIN_MIN + (MARGIN_MAX - MARGIN_MIN) * _stable_ratio(product_id, 'margin:'), 4)


def product_unit_price(product_id):
    """产品标准售价（元/件）= 单位成本 ÷ (1 - 目标毛利率)"""
    return round(product_unit_cost(product_id) / (1 - product_gross_margin(product_id)), 2)


def split_cost(total_cost):
    """把总成本按 物料/人工/制造费用 结构拆开（带少量随机扰动）"""
    weights = [mix * random.uniform(0.94, 1.06) for mix in COST_MIX]
    total_w = sum(weights)
    material_cost = round(total_cost * weights[0] / total_w, 2)
    labor_cost = round(total_cost * weights[1] / total_w, 2)
    mfg_cost = round(total_cost - material_cost - labor_cost, 2)
    return material_cost, labor_cost, mfg_cost

# ============================================================
# 数据量配置（约 200 万级）
# ============================================================

CUSTOMER_COUNT = 300       # 客户数
PRODUCT_COUNT = 200        # 产品数
MATERIAL_COUNT = 200       # 物料数
WORKSHOP_COUNT = 6         # 车间数
SUPPLIER_COUNT = 100       # 供应商数
SALE_ORDER_COUNT = 1000000  # 销售订单100万
WORKORDER_COUNT = 500000   # 生产工单50万
STOCK_IO_COUNT = 500000    # 出入库50万
EQUIPMENT_COUNT = 4        # 设备数

# ============================================================
# 车间差异化配置（让各车间表现不同）
# ============================================================

WORKSHOP_CONFIG = {
    '冲压车间': {'产能基准': 85, '良率基准': 88, '产能波动': 8, '良率波动': 8},
    '焊接车间': {'产能基准': 75, '良率基准': 96, '产能波动': 6, '良率波动': 4},
    '装配车间': {'产能基准': 92, '良率基准': 92, '产能波动': 6, '良率波动': 6},
    '涂装车间': {'产能基准': 65, '良率基准': 82, '产能波动': 10, '良率波动': 10},
    '机加工车间': {'产能基准': 80, '良率基准': 94, '产能波动': 6, '良率波动': 5},
    '质检中心': {'产能基准': 70, '良率基准': 98, '产能波动': 5, '良率波动': 3},
}

# ============================================================
# 特殊事件（某天销售额暴涨）
# ============================================================

SPECIAL_DATES = {
    datetime.date(2025, 11, 11): 2.2,   # 双11大促
    datetime.date(2025, 12, 12): 2.0,   # 双12大促
    datetime.date(2026, 1, 1): 2.0,     # 元旦
    datetime.date(2026, 3, 15): 1.8,    # 春季采购节
    datetime.date(2026, 6, 18): 2.2,    # 618大促
}
# ============================================================
# 二、初始化
# ============================================================
fake = Faker('zh_CN')
conn = pymysql.connect(**DB_CONFIG)
cursor = conn.cursor()
# ============================================================
# 三、ID 池（内存缓存维度表 ID）
# ============================================================
customer_ids = []
product_ids = []
material_ids = []
workshop_ids = []
supplier_ids = []
workorder_ids = []
order_ids = []

# ============================================================
# 四、工具函数
# ============================================================

def random_date(start, end):
    """生成随机日期"""
    return fake.date_between(start_date=start, end_date=end)

def get_season_factor(date):
    """
    季节性因子：12月/1月高，2月低
    返回倍数，用于调整订单金额
    """
    month = date.month
    if month == 12 or month == 1:
        return random.uniform(1.8, 2.8)   # 年底促销
    elif month == 6 or month == 7:
        return random.uniform(1.4, 2.2)   # 年中促销
    elif month == 2:
        return random.uniform(0.3, 0.6)   # 春节
    else:
        return random.uniform(0.6, 1.4)

def get_trend_factor(date, start_date, end_date):
    """
    长期趋势：9个月整体上升 25%
    """
    total_days = (end_date - start_date).days
    day_index = (date - start_date).days
    progress = day_index / total_days if total_days > 0 else 0
    return 1.0 + 0.25 * progress

def batch_insert(sql, data_list, batch_size=1000):
    """批量插入"""
    for i in range(0, len(data_list), batch_size):
        batch = data_list[i:i+batch_size]
        try:
            cursor.executemany(sql, batch)
            conn.commit()
        except Exception as e:
            print(f"  批量插入失败，回滚当前批次: {e}")
            conn.rollback()
            # 逐条重试，找出问题数据
            for single in batch:
                try:
                    cursor.execute(sql, single)
                    conn.commit()
                except Exception as e2:
                    print(f"    单条插入失败，跳过: {single}")
                    continue
        print(f"  已插入 {min(i+batch_size, len(data_list))}/{len(data_list)} 条")

def generate_dirty_foreign_key(valid_ids, invalid_value='INVALID_001', dirty_prob=0.005):
    """生成外键值：大部分返回有效 ID，小部分返回无效值（脏数据）"""
    if random.random() < dirty_prob:
        return invalid_value
    return random.choice(valid_ids) if valid_ids else None

# ============================================================
# 五、生成维度表数据
# ============================================================

def generate_customer():
    """生成客户维度表（帕累托分布：20% 客户贡献 80% 金额）"""
    print("1/11 生成客户数据...")
    sql = """
        INSERT INTO erp_db.customer 
        (customer_id, customer_name, region, grade, type, industry, contact_person, contact_phone)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """
    
    customer_names = [
        '海尔智能科技有限公司', '美的电器制造集团', '格力空调设备有限公司', 'TCL电子科技股份',
        '长虹电器股份公司', '海信视像科技集团', '创维数字技术公司', '康佳集团股份公司',
        '联想电子科技有限公司', '华为技术设备公司', '中兴通讯科技集团', '浪潮电子信息股份',
        '富士康工业互联公司', '比亚迪电子股份', '宁德时代新能源科技', '亿纬锂能股份公司',
        '汇川技术股份公司', '大族激光科技集团', '中联重科股份公司', '三一重工设备制造',
        '徐工机械制造集团', '柳工机械股份公司', '中车时代电气股份', '中国通号科技集团',
        '上海电气集团股份', '东方电气股份公司', '哈电集团设备制造', '中核科技股份公司',
        '宝武钢铁集团股份', '鞍钢集团股份公司', '首钢集团制造公司', '河钢集团股份公司',
        '安徽江淮汽车集团', '江铃汽车股份公司', '宇通客车股份公司', '金龙客车制造公司',
        '中国重汽集团', '陕汽集团股份', '东风汽车股份公司', '上汽集团股份公司',
        '中国兵器工业集团', '中国航天科技集团', '中国电子科技集团', '中国航空工业集团',
        '中国船舶集团', '中国核工业集团', '中国中车股份', '中国铁建股份公司',
        '华为技术有限公司', '中兴通讯股份公司', '小米科技公司', 'OPPO移动通信',
        'vivo移动通信', '传音控股股份公司', '大疆创新科技公司', '海康威视股份公司',
    ]
    
    data = []
    for _ in range(CUSTOMER_COUNT):
        # 帕累托分布：随机生成权重，使部分客户成为大客户
        pareto_weight = 1.0 / (random.random() ** 1.5)
        if pareto_weight > 3.0:
            grade = 'A'
        elif pareto_weight > 1.5:
            grade = 'B'
        elif pareto_weight > 0.8:
            grade = 'C'
        else:
            grade = 'D'
        
        data.append((
            fake.uuid4().replace('-', '')[:32],
            random.choice(customer_names),
            random.choice(['华东', '华南', '华北', '西南', '西北', '华中', '东北']),
            grade,
            random.choice(['企业', '个人', '政府']),
            fake.bs()[:20],
            fake.name(),
            fake.phone_number()
        ))
    batch_insert(sql, data)
    
    cursor.execute("SELECT customer_id FROM erp_db.customer")
    global customer_ids
    customer_ids = [row[0] for row in cursor.fetchall()]
    print(f"  ✅ 客户数据完成，共 {len(customer_ids)} 条（A级客户占比约 20%）")


def generate_product():
    """生成产品维度表（真实制造业产品名称）"""
    print("2/11 生成产品数据...")
    sql = """
        INSERT INTO erp_db.product 
        (product_id, product_name, category_l1, category_l2, category_l3, spec, unit, standard_cost)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """
    
    product_names = [
        ('智能变频空调', '家电', '空调', '变频空调'),
        ('壁挂式空调', '家电', '空调', '壁挂式'),
        ('中央空调', '家电', '空调', '中央空调'),
        ('滚筒洗衣机', '家电', '洗衣机', '滚筒式'),
        ('波轮洗衣机', '家电', '洗衣机', '波轮式'),
        ('双开门冰箱', '家电', '冰箱', '双开门'),
        ('三开门冰箱', '家电', '冰箱', '三开门'),
        ('对开门冰箱', '家电', '冰箱', '对开门'),
        ('智能电视', '家电', '电视', '智能电视'),
        ('4K超高清电视', '家电', '电视', '4K超高清'),
        ('OLED电视', '家电', '电视', 'OLED'),
        ('空气净化器', '家电', '净化器', '空气净化'),
        ('净水器', '家电', '净水器', 'RO反渗透'),
        ('洗碗机', '家电', '洗碗机', '嵌入式'),
        ('微波炉', '家电', '微波炉', '智能微波'),
        ('工业机器人', '工业设备', '机器人', '六轴机器人'),
        ('焊接机器人', '工业设备', '机器人', '焊接机器人'),
        ('搬运机器人', '工业设备', '机器人', 'AGV搬运'),
        ('数控机床', '工业设备', '机床', 'CNC数控'),
        ('加工中心', '工业设备', '机床', '立式加工中心'),
        ('注塑机', '工业设备', '注塑', '卧式注塑'),
        ('冲压机', '工业设备', '冲压', '机械式冲压'),
        ('液压冲压机', '工业设备', '冲压', '液压式'),
        ('激光切割机', '工业设备', '切割', '光纤激光'),
        ('等离子切割机', '工业设备', '切割', '等离子'),
        ('自动化流水线', '工业设备', '自动化', '装配流水线'),
        ('喷涂生产线', '工业设备', '自动化', '静电喷涂'),
        ('包装生产线', '工业设备', '自动化', '自动包装'),
        ('智能电表', '电子', '仪表', '智能电表'),
        ('工业传感器', '电子', '传感器', '压力传感器'),
        ('温度传感器', '电子', '传感器', '温度传感'),
        ('湿度传感器', '电子', '传感器', '湿度传感'),
        ('PLC控制器', '电子', '控制器', '可编程控制器'),
        ('变频器', '电子', '控制器', '变频调速'),
        ('伺服驱动器', '电子', '控制器', '伺服驱动'),
        ('工业电源', '电子', '电源', '开关电源'),
        ('UPS电源', '电子', '电源', '不间断电源'),
        ('电路板', '电子', 'PCB', 'PCB电路板'),
        ('控制面板', '电子', '面板', '人机界面'),
        ('触摸屏', '电子', '面板', '工业触摸屏'),
        ('工业相机', '电子', '视觉', '机器视觉'),
        ('条码扫描器', '电子', '识别', '二维码扫描'),
        ('RFID读写器', '电子', '识别', '射频识别'),
        ('工业交换机', '电子', '网络', '工业以太网'),
        ('无线模块', '电子', '通信', '无线传输'),
        ('步进电机', '零部件', '电机', '步进电机'),
        ('伺服电机', '零部件', '电机', '伺服电机'),
        ('行星减速器', '零部件', '传动', '行星减速器'),
        ('深沟球轴承', '零部件', '传动', '深沟球轴承'),
        ('滚珠丝杠', '零部件', '传动', '精密丝杠'),
        ('线性导轨', '零部件', '传动', '线性导轨'),
        ('标准气缸', '零部件', '气动', '标准气缸'),
        ('电磁换向阀', '零部件', '气动', '电磁换向阀'),
        ('液压油缸', '零部件', '液压', '液压油缸'),
        ('液压泵', '零部件', '液压', '齿轮泵'),
        ('O型密封圈', '零部件', '密封', 'O型密封圈'),
        ('不锈钢螺丝', '零部件', '紧固件', '不锈钢螺丝'),
        ('六角螺母', '零部件', '紧固件', '六角螺母'),
        ('平垫圈', '零部件', '紧固件', '平垫圈'),
        ('梅花联轴器', '零部件', '传动', '梅花联轴器'),
    ]
    
    data = []
    for _ in range(PRODUCT_COUNT):
        name, l1, l2, l3 = random.choice(product_names)
        data.append((
            fake.uuid4().replace('-', '')[:32],
            name,
            l1, l2, l3,
            fake.bothify(text='??-###-??'),
            random.choice(['台', '套', '个']),
            round(random.uniform(500, 20000), 2)
        ))
    batch_insert(sql, data)
    
    cursor.execute("SELECT product_id FROM erp_db.product")
    global product_ids
    product_ids = [row[0] for row in cursor.fetchall()]
    print(f"  ✅ 产品数据完成，共 {len(product_ids)} 条")


def generate_material():
    """生成物料维度表（真实制造业物料名称）"""
    print("3/11 生成物料数据...")
    sql = """
        INSERT INTO erp_db.material 
        (material_id, material_name, category, sub_category, spec, unit, safety_stock, standard_cost)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """
    
    material_names = [
        ('PCB电路板', '原材料', '电子件', 'FR-4双面板'),
        ('IC芯片', '原材料', '电子件', 'MCU主控芯片'),
        ('电阻', '原材料', '电子件', '贴片电阻'),
        ('电容', '原材料', '电子件', '电解电容'),
        ('继电器', '原材料', '电子件', '电磁继电器'),
        ('连接器', '原材料', '电子件', '排针连接器'),
        ('接插件', '原材料', '电子件', '端子排'),
        ('电线电缆', '原材料', '电子件', 'RVV电缆'),
        ('电源线', '原材料', '电子件', '三芯电源线'),
        ('信号线', '原材料', '电子件', '屏蔽双绞线'),
        ('保险丝', '原材料', '电子件', '熔断器'),
        ('开关', '原材料', '电子件', '按钮开关'),
        ('指示灯', '原材料', '电子件', 'LED指示灯'),
        ('蜂鸣器', '原材料', '电子件', '压电蜂鸣器'),
        ('散热片', '原材料', '电子件', '铝制散热片'),
        ('碳素钢', '原材料', '结构件', 'Q235碳素钢'),
        ('不锈钢', '原材料', '结构件', '304不锈钢'),
        ('铝合金型材', '原材料', '结构件', '6061铝合金'),
        ('铜排', '原材料', '结构件', 'T2紫铜排'),
        ('热轧钢板', '原材料', '结构件', '热轧钢板'),
        ('冷轧钢板', '原材料', '结构件', '冷轧钢板'),
        ('镀锌钢板', '原材料', '结构件', '镀锌钢板'),
        ('等边角钢', '原材料', '结构件', '等边角钢'),
        ('碳素槽钢', '原材料', '结构件', '碳素槽钢'),
        ('方钢管', '原材料', '结构件', '方钢管'),
        ('圆钢管', '原材料', '结构件', '圆钢管'),
        ('不锈钢波纹管', '原材料', '结构件', '不锈钢波纹管'),
        ('压缩弹簧', '原材料', '结构件', '压缩弹簧'),
        ('不锈钢螺丝', '原材料', '结构件', '不锈钢螺丝'),
        ('拉铆钉', '原材料', '结构件', '拉铆钉'),
        ('ABS注塑件', '半成品', '塑胶件', 'ABS注塑件'),
        ('PC注塑件', '半成品', '塑胶件', 'PC注塑件'),
        ('O型密封圈', '原材料', '塑胶件', 'O型密封圈'),
        ('橡胶密封垫', '原材料', '塑胶件', '橡胶密封垫'),
        ('EPE珍珠棉', '辅料', '包材', 'EPE珍珠棉'),
        ('瓦楞纸箱', '辅料', '包材', '瓦楞纸箱'),
        ('不干胶标签', '辅料', '包材', '不干胶标签'),
        ('PE缠绕膜', '辅料', '包材', 'PE缠绕膜'),
        ('封箱胶带', '辅料', '包材', '封箱胶带'),
        ('气泡缓冲膜', '辅料', '包材', '气泡缓冲膜'),
        ('步进电机', '半成品', '五金', '步进电机'),
        ('伺服电机', '半成品', '五金', '伺服电机'),
        ('行星减速器', '半成品', '五金', '行星减速器'),
        ('深沟球轴承', '原材料', '五金', '深沟球轴承'),
        ('精密丝杠', '原材料', '五金', '精密丝杠'),
        ('线性导轨', '原材料', '五金', '线性导轨'),
        ('标准气缸', '原材料', '五金', '标准气缸'),
        ('电磁换向阀', '原材料', '五金', '电磁换向阀'),
        ('液压油缸', '原材料', '五金', '液压油缸'),
        ('梅花联轴器', '原材料', '五金', '梅花联轴器'),
        ('抗磨液压油', '辅料', '油品', '抗磨液压油'),
        ('齿轮润滑油', '辅料', '油品', '齿轮润滑油'),
        ('乳化切削液', '辅料', '油品', '乳化切削液'),
        ('碳钢焊条', '辅料', '焊材', '碳钢焊条'),
        ('气体保护焊丝', '辅料', '焊材', '气体保护焊丝'),
        ('高纯氩气', '辅料', '气体', '高纯氩气'),
        ('CO2气体', '辅料', '气体', 'CO2气体'),
        ('防锈油漆', '辅料', '涂料', '防锈油漆'),
        ('油漆稀释剂', '辅料', '涂料', '油漆稀释剂'),
        ('水磨砂纸', '辅料', '耗材', '水磨砂纸'),
    ]
    
    data = []
    for _ in range(MATERIAL_COUNT):
        name, category, sub, spec = random.choice(material_names)
        data.append((
            fake.uuid4().replace('-', '')[:32],
            name,
            category, sub, spec,
            random.choice(['个', '套', '米', '公斤', '片']),
            random.randint(0, 1000),
            round(random.uniform(5, 5000), 2)
        ))
    batch_insert(sql, data)
    
    cursor.execute("SELECT material_id FROM erp_db.material")
    global material_ids
    material_ids = [row[0] for row in cursor.fetchall()]
    print(f"  ✅ 物料数据完成，共 {len(material_ids)} 条")


def generate_workshop():
    """生成车间维度表"""
    print("4/11 生成车间数据...")
    sql = """
        INSERT INTO mes_db.workshop 
        (workshop_id, workshop_name, production_line, workshop_type, capacity_per_day)
        VALUES (%s, %s, %s, %s, %s)
    """
    data = []
    workshop_names = ['冲压车间', '焊接车间', '装配车间', '涂装车间', '机加工车间', '质检中心']
    for i, name in enumerate(workshop_names[:WORKSHOP_COUNT]):
        data.append((
            fake.uuid4().replace('-', '')[:32],
            name,
            f'{random.choice(["一", "二", "三"])}车间',
            name.replace('车间', ''),
            random.randint(500, 5000)
        ))
    batch_insert(sql, data)
    
    cursor.execute("SELECT workshop_id FROM mes_db.workshop")
    global workshop_ids
    workshop_ids = [row[0] for row in cursor.fetchall()]
    print(f"  ✅ 车间数据完成，共 {len(workshop_ids)} 条")


def generate_supplier():
    """生成供应商维度表"""
    print("5/11 生成供应商数据...")
    sql = """
        INSERT INTO wms_db.supplier 
        (supplier_id, supplier_name, supply_category, cooperation_grade, cooperation_status, contact_person, contact_phone)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    for _ in range(SUPPLIER_COUNT):
        data.append((
            fake.uuid4().replace('-', '')[:32],
            fake.company()[:40],
            random.choice(['电子元器件', '结构件', '包材', '五金', '化工材料']),
            random.choice(['A', 'B', 'C', 'D']),
            random.choice(['合作中', '合作中', '合作中', '已终止']),
            fake.name(),
            fake.phone_number()
        ))
    batch_insert(sql, data)
    
    cursor.execute("SELECT supplier_id FROM wms_db.supplier")
    global supplier_ids
    supplier_ids = [row[0] for row in cursor.fetchall()]
    print(f"  ✅ 供应商数据完成，共 {len(supplier_ids)} 条")


# ============================================================
# 六、生成事实表数据
# ============================================================

def generate_sale_order():
    """生成销售订单事实表（含季节因子 + 趋势因子 + 特殊事件）"""
    print("6/11 生成销售订单数据...")
    sql = """
        INSERT INTO erp_db.sale_order 
        (order_id, customer_id, product_id, order_date, order_amount, tax_amount, 
         discount_amount, net_amount, order_status, delivery_date, payment_date, region, quantity)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    regions = ['华东', '华南', '华北', '西南', '西北', '华中', '东北']

    for _ in range(SALE_ORDER_COUNT):
        order_date = random_date(START_DATE, END_DATE)

        # 脏数据：0.5% 概率 product_id 为无效值
        product_id = generate_dirty_foreign_key(product_ids, 'INVALID_001', DIRTY_RATIO)

        # 需求量（季节/趋势/特殊事件体现为"数量"波动，单价保持产品标准价）
        season = get_season_factor(order_date)
        trend = get_trend_factor(order_date, START_DATE, END_DATE)
        quantity = max(1, int(random.randint(ORDER_QTY_MIN, ORDER_QTY_MAX)
                              * season * trend * random.uniform(0.85, 1.15)))
        if order_date in SPECIAL_DATES:
            quantity = int(quantity * SPECIAL_DATES[order_date])

        # 单价 = 产品标准售价（含少量议价浮动），金额 = 单价 × 数量
        price = product_unit_price(product_id) * random.uniform(0.98, 1.02)
        amount = round(price * quantity, 2)
        tax = round(amount * 0.13, 2)
        discount = round(amount * random.uniform(0, 0.15), 2) if random.random() > 0.3 else 0
        net = round(amount + tax - discount, 2)

        # 脏数据：1% 概率制造异常金额
        if random.random() < DIRTY_RATIO:
            amount = random.choice([-999, 99999999, 0])
            tax = 0
            net = amount

        # 脏数据：0.5% 概率 customer_id 为空
        if random.random() < DIRTY_RATIO / 2:
            customer_id = None
        else:
            customer_id = random.choice(customer_ids)

        # 订单状态与交付/回款（口径：按时交付 = 发货日期 ≤ 下单日期 + DELIVERY_SLA_DAYS）
        roll = random.random()
        if roll < 0.10:                     # 取消
            status, delivery_date, payment_date = '已取消', None, None
        elif roll < 0.12:                   # 作废
            status, delivery_date, payment_date = '已作废', None, None
        elif roll < 0.20:                   # 已提交未发货
            status, delivery_date, payment_date = '已提交', None, None
        else:
            if random.random() < 0.88:      # 88% 按时交付
                delivery_date = order_date + datetime.timedelta(days=random.randint(1, DELIVERY_SLA_DAYS))
            else:                           # 12% 迟到
                delivery_date = order_date + datetime.timedelta(
                    days=random.randint(DELIVERY_SLA_DAYS + 1, 40))
            if random.random() < 0.03:      # 3% 交付后退货（退货金额进 return_amt）
                status, payment_date = '已退货', None
            else:
                status = '已完成' if random.random() < 0.7 else '已发货'
                # 回款：80% 在交付后 40 天内回款，其余留作回款滞后
                payment_date = (delivery_date + datetime.timedelta(days=random.randint(0, 40))
                                if random.random() < 0.8 else None)

        data.append((
            fake.uuid4().replace('-', '')[:32],
            customer_id,
            product_id,
            order_date,
            amount, tax, discount, net,
            status,
            delivery_date,
            payment_date,
            random.choice(regions),
            quantity
        ))

    batch_insert(sql, data)

    cursor.execute("SELECT order_id FROM erp_db.sale_order")
    global order_ids
    order_ids = [row[0] for row in cursor.fetchall()]
    print(f"  ✅ 销售订单完成，共 {len(order_ids)} 条（含季节波动和趋势上升）")


def generate_workorder():
    """生成生产工单事实表（含车间差异化）"""
    print("7/11 生成生产工单数据...")
    sql = """
        INSERT INTO mes_db.produce_workorder 
        (workorder_id, product_id, workshop_id, plan_qty, actual_qty, qualified_qty, defect_qty,
         defect_type, plan_start_date, plan_end_date, actual_start_date, actual_end_date, 
         workorder_status, labor_hours, material_loss)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    defect_types = ['尺寸偏差', '外观缺陷', '性能失效', '其他']

    # 车间 ID → 名称 一次性load成字典（原实现每生成一条工单就 SELECT 一次，
    # 50 万次单行查询是整脚本跑 8 小时的主要原因）
    cursor.execute("SELECT workshop_id, workshop_name FROM mes_db.workshop")
    workshop_name_map = {wid: wname for wid, wname in cursor.fetchall()}

    for _ in range(WORKORDER_COUNT):
        workshop_id = random.choice(workshop_ids)
        workshop_name = workshop_name_map.get(workshop_id, '未知车间')

        config = WORKSHOP_CONFIG.get(workshop_name, {'产能基准': 80, '良率基准': 92, '产能波动': 8, '良率波动': 6})

        # 计划产量区间收窄，使"总产量 ≈ 总销量 × 1.1"，避免产量远大于销量
        plan_qty = random.randint(PLAN_QTY_MIN, PLAN_QTY_MAX)

        # 根据车间配置计算产能达成率和良率
        capacity_achieved = config['产能基准'] + random.uniform(-config['产能波动'], config['产能波动'])
        capacity_achieved = max(min(capacity_achieved, 100), 40)

        # 脏数据：0.5% 概率产量异常（放在最前，保证 良品+不良 = 实际产量 恒成立）
        dirty_qty = random.random() < DIRTY_RATIO
        if dirty_qty:
            actual_qty = plan_qty * 10
            qualified_rate = random.uniform(50, 70)
        else:
            actual_qty = int(plan_qty * capacity_achieved / 100)
            # 良率 = 基准 + 波动
            qualified_rate = config['良率基准'] + random.uniform(-config['良率波动'], config['良率波动'])
            qualified_rate = max(min(qualified_rate, 100), 70)

        qualified = int(actual_qty * qualified_rate / 100) if actual_qty > 0 else 0
        defect = actual_qty - qualified if actual_qty > 0 else 0

        # 脏数据：0.5% 概率 product_id 为空
        if random.random() < DIRTY_RATIO / 2:
            product_id = None
        else:
            product_id = random.choice(product_ids)

        # 工时与物料损耗随实际产量同比例变化（原实现是与产量无关的随机数）
        labor_hours = round(actual_qty * random.uniform(0.03, 0.08), 2)
        material_loss = round(actual_qty * product_unit_cost(product_id or 'UNKNOWN')
                              * random.uniform(0.005, 0.02), 2)

        plan_start = random_date(START_DATE, END_DATE)
        plan_end = random_date(plan_start, plan_start + datetime.timedelta(days=30))

        # 工单状态及实际日期
        status = random.choice(['未开工', '生产中', '已完工', '已关闭', '已逾期'])
        if status in ['已完工', '已关闭']:
            actual_start = random_date(plan_start, plan_start + datetime.timedelta(days=5))
            actual_end = random_date(actual_start, plan_end + datetime.timedelta(days=7))
        elif status == '生产中':
            actual_start = random_date(plan_start, plan_start + datetime.timedelta(days=5))
            actual_end = None
        else:
            actual_start = None
            actual_end = None

        # 脏数据：0.5% 概率 product_id 为空（已在上面统一处理，此处不再重复生成）

        data.append((
            fake.uuid4().replace('-', '')[:32],
            product_id,
            workshop_id,
            plan_qty,
            max(0, actual_qty),
            max(0, qualified),
            max(0, defect),
            random.choice(defect_types) if defect > 0 else None,
            plan_start, plan_end,
            actual_start, actual_end,
            status,
            labor_hours,
            material_loss
        ))

    batch_insert(sql, data)

    cursor.execute("SELECT workorder_id FROM mes_db.produce_workorder")
    global workorder_ids
    workorder_ids = [row[0] for row in cursor.fetchall()]
    print(f"  ✅ 生产工单完成，共 {len(workorder_ids)} 条（各车间表现差异化）")


def generate_stock_io():
    """生成出入库明细事实表（与库存快照联动，快照为真实结存）

    修正背景：原实现里出入库流水与库存快照是两套互不相关的随机数
    （快照 stock_qty 每天独立 random(0,2000)），导致库存周转天数没有业务含义。
    现在改为：以期初库存为起点，按天累加 IN - OUT 得到真实结存，
    同一天既写出入库流水、也写库存快照（200 物料 × 3 仓库 = 600 条/天）。
    """
    print("8/11 生成出入库明细 + 库存快照数据...")
    sql = """
        INSERT INTO wms_db.stock_io_detail 
        (io_id, material_id, warehouse_id, io_type, io_qty, io_amount, unit_price, io_date,
         supplier_id, workorder_id, order_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    snap_sql = """
        INSERT INTO wms_db.stock_snapshot 
        (snapshot_id, material_id, warehouse_id, snapshot_date, stock_qty, stock_amount)
        VALUES (%s, %s, %s, %s, %s, %s)
    """
    warehouses = ['原材料仓', '半成品仓', '成品仓']
    combos = [(m, w) for m in material_ids for w in warehouses]
    balance = {combo: random.randint(50, 800) for combo in combos}   # 期初库存（件）

    io_rows, snap_rows = [], []
    io_total, snap_total = 0, 0
    current_date = SNAPSHOT_START
    while current_date <= SNAPSHOT_END:
        for material_id, warehouse_id in combos:
            price = material_unit_price(material_id)
            for _ in range(random.randint(1, 4)):
                if random.random() < 0.5:
                    qty = random.randint(10, 300)
                    io_type = 'IN'
                    balance[(material_id, warehouse_id)] += qty
                    supplier_id = random.choice(supplier_ids) if random.random() > 0.5 else None
                    workorder_id, order_id = None, None
                else:
                    # 出库量不能超过当前结存，保证库存永不为负
                    qty = min(random.randint(10, 300), balance[(material_id, warehouse_id)])
                    if qty <= 0:
                        continue
                    io_type = 'OUT'
                    balance[(material_id, warehouse_id)] -= qty
                    supplier_id = None
                    workorder_id = random.choice(workorder_ids) if random.random() > 0.5 else None
                    order_id = random.choice(order_ids) if random.random() > 0.3 else None

                amount = round(qty * price, 2)
                if random.random() < DIRTY_RATIO:      # 脏数据：金额异常
                    amount = -9999

                io_rows.append((
                    fake.uuid4().replace('-', '')[:32],
                    material_id,
                    warehouse_id,
                    io_type,
                    qty,
                    amount,
                    price,
                    current_date,
                    supplier_id,
                    workorder_id,
                    order_id
                ))

            stock_qty = balance[(material_id, warehouse_id)]
            snap_rows.append((
                fake.uuid4().replace('-', '')[:32],
                material_id,
                warehouse_id,
                current_date,
                stock_qty,
                round(stock_qty * price, 2)
            ))

        # 分批落库，避免 60 万行全部堆在内存里
        if len(io_rows) >= 50000:
            batch_insert(sql, io_rows); io_total += len(io_rows); io_rows = []
        if len(snap_rows) >= 50000:
            batch_insert(snap_sql, snap_rows); snap_total += len(snap_rows); snap_rows = []
        current_date += datetime.timedelta(days=1)

    if io_rows:
        batch_insert(sql, io_rows); io_total += len(io_rows)
    if snap_rows:
        batch_insert(snap_sql, snap_rows); snap_total += len(snap_rows)

    print(f"  ✅ 出入库明细完成，共 {io_total} 条")
    print(f"  ✅ 库存快照完成，共 {snap_total} 条（结存 = 期初 + 累计入库 - 累计出库）")


# 说明：原 generate_stock_snapshot() 已并入 generate_stock_io()，
#      因为库存快照必须是出入库流水的累加结存，两者不能各自独立随机生成。


def generate_cost_voucher():
    """生成成本凭证事实表

    成本口径 = 产品标准单位成本 × 工单实际产量 ×(1 ± 4%)，再按 物料/人工/制造费用 拆分。
    月份取工单的计划开工月份，保证"成本月份"与"生产月份"一致（原实现月份是随机取的）。
    """
    print("10/11 生成成本凭证数据...")
    sql = """
        INSERT INTO erp_db.cost_voucher 
        (voucher_id, product_id, workshop_id, workorder_id, material_cost, labor_cost, mfg_cost, total_cost, cost_month)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []

    cursor.execute("""
        SELECT workorder_id, product_id, workshop_id, actual_qty, plan_start_date
        FROM mes_db.produce_workorder
    """)
    workorders = cursor.fetchall()
    for workorder_id, product_id, workshop_id, actual_qty, plan_start_date in workorders:
        qty = actual_qty or 0
        unit_cost = product_unit_cost(product_id or 'UNKNOWN')
        total_cost = round(unit_cost * qty * random.uniform(0.96, 1.04), 2)
        material_cost, labor_cost, mfg_cost = split_cost(total_cost)
        data.append((
            fake.uuid4().replace('-', '')[:32],
            product_id,
            workshop_id,
            workorder_id,
            material_cost,
            labor_cost,
            mfg_cost,
            total_cost,
            plan_start_date.strftime('%Y-%m') if plan_start_date else START_DATE.strftime('%Y-%m')
        ))

    batch_insert(sql, data)
    print(f"  ✅ 成本凭证完成，共 {len(data)} 条")


def generate_equipment_runtime():
    """生成设备运行记录事实表"""
    print("11/11 生成设备运行数据...")
    sql = """
        INSERT INTO mes_db.equipment_runtime 
        (record_id, equipment_id, workshop_id, record_date, runtime_min, idle_min, fault_min, maintain_min, total_min)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    data = []
    equipment_names = ['设备A-001', '设备A-002', '设备B-001', '设备C-001']
    current_date = START_DATE
    while current_date <= END_DATE:
        for eq_name in equipment_names[:EQUIPMENT_COUNT]:
            # 四项时间之和恒等于 1440 分钟，这样 OEE = 运行时间 / 1440 才有意义
            # （原实现四项各自随机、加起来不等于 1440，OEE 无法计算）
            fault = random.randint(0, 120) if random.random() > 0.7 else 0
            maintain = random.randint(0, 90) if random.random() > 0.5 else 0
            idle = random.randint(60, 300)
            runtime = max(0, 1440 - idle - fault - maintain)
            data.append((
                fake.uuid4().replace('-', '')[:32],
                eq_name,
                random.choice(workshop_ids),
                current_date,
                runtime,
                idle,
                fault,
                maintain,
                runtime + idle + fault + maintain
            ))
        current_date += datetime.timedelta(days=1)

    batch_insert(sql, data)
    print(f"  ✅ 设备运行数据完成，共 {len(data)} 条")


# ============================================================
# 七、外键完整性验证
# ============================================================

def verify_foreign_keys():
    """验证外键关联完整性"""
    print("\n验证外键关联...")
    checks = [
        ("销售订单-客户",
         "SELECT COUNT(*) FROM erp_db.sale_order o LEFT JOIN erp_db.customer c ON o.customer_id = c.customer_id WHERE o.customer_id IS NOT NULL AND c.customer_id IS NULL"),
        ("销售订单-产品",
         "SELECT COUNT(*) FROM erp_db.sale_order o LEFT JOIN erp_db.product p ON o.product_id = p.product_id WHERE o.product_id IS NOT NULL AND p.product_id IS NULL AND o.product_id != 'INVALID_001'"),
        ("生产工单-产品",
         "SELECT COUNT(*) FROM mes_db.produce_workorder w LEFT JOIN erp_db.product p ON w.product_id = p.product_id WHERE w.product_id IS NOT NULL AND p.product_id IS NULL"),
        ("生产工单-车间",
         "SELECT COUNT(*) FROM mes_db.produce_workorder w LEFT JOIN mes_db.workshop ws ON w.workshop_id = ws.workshop_id WHERE w.workshop_id IS NOT NULL AND ws.workshop_id IS NULL"),
        ("出入库-物料",
         "SELECT COUNT(*) FROM wms_db.stock_io_detail s LEFT JOIN erp_db.material m ON s.material_id = m.material_id WHERE s.material_id IS NOT NULL AND m.material_id IS NULL AND s.material_id != 'INVALID_MAT'"),
        ("库存快照-物料",
         "SELECT COUNT(*) FROM wms_db.stock_snapshot s LEFT JOIN erp_db.material m ON s.material_id = m.material_id WHERE s.material_id IS NOT NULL AND m.material_id IS NULL"),
    ]

    all_passed = True
    for name, sql in checks:
        cursor.execute(sql)
        count = cursor.fetchone()[0]
        status = "✅" if count == 0 else f"⚠️ {count}条无关联"
        print(f"  {name}: {status}")
        if count > 0:
            all_passed = False

    return all_passed


# ============================================================
# 八、主程序
# ============================================================

def reset_source_tables():
    """清空 11 张源表，保证脚本可重复生成（原实现不清表，重复运行会成倍累加数据）"""
    print("🧹 清空源表（保证可重复生成，可用 --append 关闭）...")
    tables = [
        'erp_db.customer', 'erp_db.product', 'erp_db.material', 'erp_db.sale_order', 'erp_db.cost_voucher',
        'mes_db.workshop', 'mes_db.produce_workorder', 'mes_db.equipment_runtime',
        'wms_db.supplier', 'wms_db.stock_io_detail', 'wms_db.stock_snapshot',
    ]
    for t in tables:
        cursor.execute(f"TRUNCATE TABLE {t}")
    conn.commit()
    print(f"  ✅ 已清空 {len(tables)} 张表")


def main():
    print("=" * 60)
    print("🚀 开始生成仿真数据（价格/成本/产量自洽版）")
    print(f"📅 时间范围: {START_DATE} ~ {END_DATE}（库存快照 {SNAPSHOT_START} ~ {SNAPSHOT_END}）")
    print(f"📊 脏数据比例: {DIRTY_RATIO * 100}%")
    print(f"📈 销售订单: {SALE_ORDER_COUNT:,} 条")
    print(f"📈 生产工单: {WORKORDER_COUNT:,} 条")
    print(f"📈 出入库明细: 按天生成（约 {STOCK_IO_COUNT:,} 条）+ 库存快照 600 条/天")
    print("=" * 60)

    try:
        if RESET_BEFORE_GENERATE:
            reset_source_tables()

        # 生成维度表
        generate_customer()
        generate_product()
        generate_material()
        generate_workshop()
        generate_supplier()

        # 生成事实表（顺序有依赖：订单/工单 → 成本凭证 → 出入库&库存快照）
        generate_sale_order()
        generate_workorder()
        generate_cost_voucher()
        generate_stock_io()
        generate_equipment_runtime()

        # 验证
        print("\n" + "=" * 60)
        print("外键完整性验证结果：")
        passed = verify_foreign_keys()

        if passed:
            print("\n🎉 所有数据生成完成！外键关联全部正常！")
            print(f"📊 总数据量约 {SALE_ORDER_COUNT + WORKORDER_COUNT + STOCK_IO_COUNT:,} 行")
        else:
            print("\n⚠️ 数据生成完成，但存在部分外键无法关联（可能是脏数据）")

    except Exception as e:
        print(f"\n❌ 执行失败: {e}")
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    if '--append' in sys.argv:
        RESET_BEFORE_GENERATE = False
    main()