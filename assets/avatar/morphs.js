// morphs.js — ขับรูปหน้าที่ VRM expression ไปไม่ถึง
//
// ## 🔴 ทำไมต้องมีชั้นนี้ ทั้งที่มี expressionManager อยู่แล้ว
//
// expression ของ VRM 1.0 มีแค่สิบสี่ชื่อ และของโมเดลที่แถมมาผูกแบบนี้
// (อ่านจากไฟล์ minde.vrm ตรง ๆ ไม่ได้เดา):
//
//     happy → Fcl_ALL_Joy      angry → Fcl_ALL_Angry
//     sad   → Fcl_ALL_Sorrow   relaxed → Fcl_ALL_Fun
//     surprised → Fcl_ALL_Surprised
//     blink/blinkLeft/blinkRight → Fcl_EYE_Close*
//     aa/ih/ou/ee/oh → Fcl_MTH_*
//
// ทุกตัวเป็น **รูปหน้ารวมทั้งใบ** — ไม่มีทางไหนเลยที่ขยับ*เฉพาะคิ้ว*ได้
// ทั้งที่โมเดลมี `Fcl_BRW_Angry/Fun/Joy/Sorrow/Surprised` อยู่ครบห้าตัว
// และ**ไม่มี expression ตัวไหนผูกมันไว้** — morph ที่ปั้นมาแล้วไม่มีใครใช้
//
// ## 🔴 ซ้อนกับ Fcl_ALL_* ไม่ได้
//
// `Fcl_ALL_Joy` มีการขยับคิ้วรวมอยู่ในตัวมันเองแล้ว · ขับ `happy` เต็มค่า
// พร้อมกับ `Fcl_BRW_Joy` เต็มค่า = คิ้วถูกดันสองรอบ หน้าจะบิด
// ผู้เรียกต้องลดน้ำหนักคิ้วลงตามสีหน้ารวมที่ใส่อยู่ (ดู avatar.js `_brows`)
//
// ## ต้องเขียนหลัง vrm.update()
//
// `VRMExpressionManager` รีเซ็ต morph ที่**มัน**ผูกไว้เป็นศูนย์ทุกเฟรมก่อน
// ใส่ค่าใหม่ · ตัวที่ไม่มีใครผูก (BRW ทั้งหมด) มันไม่แตะ แต่ลำดับที่ปลอดภัย
// กว่าคือเขียนทีหลังเสมอ จะได้ไม่ต้องพึ่งรายละเอียดภายในของไลบรารี

/**
 * ชื่อ morph ที่เรารู้จัก เรียงตามลำดับที่จะลอง
 *
 * มีหลายชื่อต่อหนึ่งความหมายเพราะชุดตัวละครมาจากคนละเครื่องมือ — VRoid ใช้
 * `Fcl_*` ส่วนคนที่ปั้นเองมักตั้งชื่อแบบ ARKit หรือภาษาอังกฤษล้วน
 * เจอตัวไหนก่อนใช้ตัวนั้น · ไม่เจอเลย = ความสามารถนั้นไม่มีในชุดนี้
 * ซึ่ง [Morphs.missing] บอกออกไปตรง ๆ แทนที่จะขยับไม่ได้เงียบ ๆ
 */
export const MORPHS = {
    browUp: ['Fcl_BRW_Surprised', 'browUp', 'brow_raise'],
    browDown: ['Fcl_BRW_Angry', 'browDown', 'brow_down'],
    browSorrow: ['Fcl_BRW_Sorrow', 'browSad', 'brow_sad'],
    browJoy: ['Fcl_BRW_Joy', 'Fcl_BRW_Fun', 'browJoy'],

    eyeWide: ['Fcl_EYE_Spread', 'Fcl_EYE_Surprised', 'eyeWide'],

    // ลิ้น — โมเดล VRoid มาตรฐาน**ไม่มี** (ตรวจแล้วกับ minde.vrm: 57 morph
    // ไม่มีลิ้นสักตัว · `Fcl_HA_*` คือ 歯 ฟัน กับ 牙 เขี้ยว) ชื่อพวกนี้จึงมี
    // ไว้รอชุดที่ปั้นลิ้นมาเอง ไม่ใช่ของที่คาดว่าจะเจอ
    tongue: ['Fcl_TNG_Out', 'tongueOut', 'Tongue_Out', 'tongue_out', 'ベロ'],
};

export class Morphs {
    constructor() {
        /** ชื่อ morph → รายการที่ต้องเขียน (mesh หลายชิ้นมีชื่อซ้ำกันได้) */
        this._index = new Map();
        /** ความสามารถ → ชื่อจริงที่เจอในชุดนี้ */
        this.found = {};
        /** ความสามารถที่ชุดนี้ทำไม่ได้ */
        this.missing = [];
    }

    /**
     * ไล่ดู morph ทั้งหมดในโมเดลครั้งเดียวตอนโหลด
     *
     * ทำครั้งเดียวเพราะ traverse ทั้งฉากทุกเฟรมคือการเดินต้นไม้ 60 ครั้ง/วินาที
     * เพื่อคำตอบที่ไม่เคยเปลี่ยน
     */
    bind(vrm) {
        this._index.clear();
        this.found = {};
        this.missing = [];

        vrm?.scene?.traverse((o) => {
            const dict = o.morphTargetDictionary;
            if (!dict || !o.morphTargetInfluences) return;
            for (const [name, i] of Object.entries(dict)) {
                if (!this._index.has(name)) this._index.set(name, []);
                this._index.get(name).push({ mesh: o, index: i });
            }
        });

        for (const [cap, names] of Object.entries(MORPHS)) {
            const hit = names.find((n) => this._index.has(n));
            if (hit) this.found[cap] = hit;
            else this.missing.push(cap);
        }
        return this;
    }

    /** ชุดนี้ทำความสามารถนี้ได้ไหม */
    can(cap) {
        return this.found[cap] !== undefined;
    }

    /**
     * ตั้งน้ำหนัก 0..1 · ชื่อที่ไม่มีคือไม่ทำอะไร **แต่รู้ล่วงหน้าแล้วว่าไม่มี**
     * ผ่าน [missing] ไม่ใช่ล้มเหลวเงียบ ๆ แบบ `expressionManager.setValue`
     */
    set(cap, weight) {
        const name = this.found[cap];
        if (!name) return false;
        const w = weight < 0 ? 0 : weight > 1 ? 1 : weight;
        for (const t of this._index.get(name)) {
            t.mesh.morphTargetInfluences[t.index] = w;
        }
        return true;
    }

    /** ทุกตัวที่เราขับ กลับเป็นศูนย์ — ใช้ตอนเลิกเชิดหุ่น */
    clear() {
        for (const cap of Object.keys(this.found)) this.set(cap, 0);
    }

    /** ให้ probe() รายงานออกไปได้ว่าชุดนี้ทำอะไรได้บ้าง */
    report() {
        return { found: { ...this.found }, missing: [...this.missing] };
    }
}
