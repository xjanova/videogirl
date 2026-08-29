# Avatar pack — ไม่ได้อยู่ใน git

โฟลเดอร์ `assets/avatar/model/` ถูก `.gitignore` ไว้ทั้งโฟลเดอร์ **โดยตั้งใจ**

## ทำไม

- **คลิปท่าทางเป็นของ Mixamo** — เงื่อนไขของเขาอนุญาตให้ *ใช้* ในงานของเรา
  แต่ไม่อนุญาตให้ *แจกไฟล์ `.fbx` ต่อ* และ repo นี้เป็น public
- **โมเดล `minde.vrm`** เป็นตัวละครของเจ้าของ ไม่ได้ตั้งใจแจก
- รวมกัน ~33 MB ไม่ควรอยู่ใน git อยู่แล้ว

BrainX ก็ใช้กติกาเดียวกัน — ไม่อยู่ใน git ไม่แนบไปกับ release

## วิธีเติมของ

คัดลอกจากเครื่องที่มี BrainX ติดตั้งอยู่:

```bash
cp "$LOCALAPPDATA/BrainX/avatar"/*.vrm  assets/avatar/model/
cp "$LOCALAPPDATA/BrainX/avatar"/*.fbx  assets/avatar/model/
cp "$LOCALAPPDATA/BrainX/avatar"/clips.json assets/avatar/model/
```

ที่อื่นที่อาจมีของ (BrainX ไล่หาตามลำดับนี้):
`ข้าง ๆ ไฟล์ exe` → `dev tree` → `Documents\vrm` → `Documents\BrainX\avatar`

## ต้องมีอะไรบ้าง

| ไฟล์ | จำเป็น | หมายเหตุ |
|---|---|---|
| `minde.vrm` | ✅ | ไม่มี = ขึ้นกรอบ placeholder แทน |
| `clips.json` | ✅ | รายการคลิปและการแมป |
| `*.fbx` (20 ไฟล์) | ทางเลือก | ไม่มีคลิป = เธอยืนนิ่ง แต่ยังคุยและขยับปากได้ |

## รู้ไว้: มีสองคลิปที่ขาดตั้งแต่ต้นทาง

`clips.json` อ้างถึง 22 คลิป แต่ในเครื่องมีจริง 20

`Bored.fbx` และ `Waiting.fbx` ไม่เคยถูกดาวน์โหลดมา (Mixamo ไม่ตอบตอนนั้น)
ทาง BrainX จงใจทิ้งชื่อไว้ใน manifest เพื่อให้ใช้ได้ทันทีเมื่อไฟล์มาถึง
`motion.js` ข้ามให้อยู่แล้ว แต่ WebView จะยิง 404 สองครั้งต่อการเปิดหนึ่งครั้ง

**สำคัญ:** `avatar_view.dart` กรอง error ให้เหลือเฉพาะ main frame แล้ว
ถ้าเผลอเอาตัวกรองนั้นออก 404 สองตัวนี้จะทำให้เธอโดนซ่อนหลัง placeholder
ทั้งที่โหลดสำเร็จ — อาการจะดูเหมือนโมเดลพัง ทั้งที่ไม่ได้พัง

## เครื่องยนต์ที่อยู่ใน git

ไฟล์พวกนี้ **อยู่** ใน repo เพราะเป็น MIT และเล็กพอ:

- `avatar.js` `motion.js` `idle.js` `lipsync.js` `framing.js` — ยกจาก BrainX
- `vendor/three` `vendor/three-vrm` `vendor/vrm-mixamo` — ดู [THIRD_PARTY.md](../../THIRD_PARTY.md)

**แหล่งความจริงของโค้ดพวกนี้คือ `xjanova/BrainX`** — แก้ที่นั่นแล้วซิงก์กลับมา
อย่าแก้แยกสองที่ ไม่งั้นบั๊กที่แก้แล้วฝั่งหนึ่งจะกลับมาอีกฝั่งหนึ่ง
