#!/usr/bin/env python3
"""อ่านรายงานที่แอปส่งเข้าระบบ bug report ของ xman studio

🔴 มีไฟล์นี้เพราะ **ผู้ช่วยต้องเช็คเองได้ ไม่ต้องขอเจ้าของแคปหน้าจอมาให้**

ปลายทาง GET เปิดสาธารณะโดยตั้งใจ (แอปในบ้านไม่มีหน้าล็อกอิน) จึงอ่านได้ด้วย
HTTP เปล่า ๆ ไม่ต้องมี SSH ไม่ต้องเข้าหน้าแอดมิน

    python tool/reports.py            รายการล่าสุดของ giggok
    python tool/reports.py 3531       อ่านฉบับเดียวทั้งฉบับ
    python tool/reports.py stats      สถิติรวมทุกสินค้า

ระบบเดียวกับที่ tping และแอปอื่นในบ้านใช้ — **อย่าสร้างที่เก็บใหม่**
(เคยหลงทำ /api/giggok/debug-report ขึ้นมาซ้อนมาแล้วหนึ่งรอบ)
"""
import json
import os
import sys
import urllib.request

BASE = os.environ.get("GIGGOK_BASE", "https://xman4289.com")
PRODUCT = os.environ.get("GIGGOK_PRODUCT", "giggok")
API = BASE.rstrip("/") + "/api/v1/bug-reports"


def get(url):
    # 🔴 ต้องมี User-Agent ปกติ · ตัวตั้งต้นของ urllib ("Python-urllib/3.x")
    # โดน WAF หน้าเว็บตอบ 403 ขณะที่ curl ผ่านฉลุย — ต่างกันแค่หัวนี้หัวเดียว
    req = urllib.request.Request(url, headers={
        "Accept": "application/json",
        "User-Agent": "giggok-tools/1.0",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def show_stats():
    d = get(API + "/stats")["data"]
    print(f"ทั้งหมด {d['total']} · ยังไม่ได้ดู {d['unanalyzed']} · ยังไม่แก้ {d['unfixed']}")
    for key in ("by_type", "by_priority", "by_status"):
        print(f"  {key}: {d.get(key)}")


def show_one(report_id):
    r = get(f"{API}/{report_id}")["data"]
    for k in ("id", "product_name", "app_version", "os_version", "report_type",
              "priority", "device_id", "created_at", "title"):
        print(f"{k:>14}: {r.get(k)}")
    print("-" * 70)
    print(r.get("description") or "(ว่าง)")


def show_list():
    d = get(f"{API}?product_name={PRODUCT}&per_page=10")
    print(f"รายงานของ {PRODUCT} ทั้งหมด {d['pagination']['total']} ฉบับ")
    if not d["data"]:
        print("  (ยังไม่มี — แปลว่ายังไม่มีใครกดส่งจากในแอป)")
    for r in d["data"]:
        print(f"  #{r['id']} [{r['report_type']}/{r['priority']}] "
              f"v{r['app_version']} · {r['os_version']}")
        print(f"      {r['title']}")
        print(f"      {r['created_at']}")


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "list"
    try:
        if arg == "stats":
            show_stats()
        elif arg.isdigit():
            show_one(arg)
        else:
            show_list()
    except Exception as e:  # noqa: BLE001 — เครื่องมือมือ ไม่ใช่โค้ดที่ปล่อยจริง
        print(f"อ่านไม่ได้ — {e}", file=sys.stderr)
        sys.exit(1)
