# สินทรัพย์และไลบรารีของคนอื่น

## อยู่ใน repo นี้

| ของ | ที่อยู่ | สัญญาอนุญาต |
|---|---|---|
| three.js **r169** | `assets/avatar/vendor/three/` | MIT — © three.js authors |
| @pixiv/three-vrm | `assets/avatar/vendor/three-vrm/` | MIT — © 2019-2026 pixiv Inc. ([LICENSE](assets/avatar/vendor/three-vrm/LICENSE)) |
| vrm-mixamo (ตัวแมปกระดูก) | `assets/avatar/vendor/vrm-mixamo/` | MIT |
| เครื่องยนต์อวาตาร์ | `assets/avatar/*.js` | ของเจ้าของเอง ยกมาจาก [xjanova/BrainX](https://github.com/xjanova/BrainX) |

three.js ไม่ได้แนบไฟล์ LICENSE มากับ dist ที่คัดลอกมา —
ต้นฉบับอยู่ที่ https://github.com/mrdoob/three.js/blob/master/LICENSE (MIT)

## **ไม่ได้** อยู่ใน repo นี้ (และห้ามใส่)

| ของ | เหตุผล |
|---|---|
| คลิปท่าทาง Mixamo (`*.fbx`) | Adobe อนุญาตให้ **ใช้** ในงาน แต่ไม่อนุญาตให้ **แจกไฟล์ต่อ** · repo นี้ public |
| `minde.vrm` | ตัวละครของเจ้าของ ไม่ได้ตั้งใจแจก |

ทั้งสองอย่างถูก `.gitignore` ทั้งโฟลเดอร์ (`assets/avatar/model/`)
และ **ห้ามแนบไปกับ GitHub Release** ด้วย — release มีแค่ APK กับ `SHA256SUMS.txt`

> APK ที่ build เสร็จจะมีคลิปฝังอยู่ข้างใน ตราบใดที่ APK นั้นใช้กันในวงเจ้าของเอง
> ก็อยู่ในขอบเขตการใช้งานปกติ แต่ถ้าจะปล่อย APK สาธารณะ ต้องเช็คเงื่อนไข
> Mixamo กับกรณีนั้นอีกรอบก่อน

## ฟอนต์

IBM Plex Sans Thai และ IBM Plex Mono — SIL Open Font License 1.1
โหลดผ่านแพ็กเกจ `google_fonts` ตอนรันครั้งแรก ไม่ได้ฝังในไบนารี

## แพ็กเกจ Flutter

ดูรายการเต็มและสัญญาอนุญาตของแต่ละตัวได้จาก:

```bash
flutter pub deps --style=list
```

ตัวหลักที่ใช้: `flutter_inappwebview` · `flutter_tts` · `google_fonts` · `provider`
`http` · `crypto` · `convert` · `path_provider` · `shared_preferences`
`package_info_plus` · `open_filex` — ทั้งหมดเป็น BSD-3 หรือ MIT
