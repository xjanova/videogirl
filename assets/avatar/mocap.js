// mocap.js — กล้องหน้าเป็นตัวเชิดหุ่น (motion capture ระดับ 1: ใบหน้า)
//
// สิ่งที่ไฟล์นี้ทำ: อ่านกล้องหน้า → MediaPipe FaceLandmarker → 52 ค่าน้ำหนัก
// ชื่อแบบ ARKit + เมทริกซ์ท่าหัว → แปลงเป็นภาษาที่ VRM เข้าใจ (aa ih ou ee oh,
// blink, lookUp/Down/Left/Right, happy/sad/surprised) แล้วให้ avatar.js เขียนลงหน้า
//
// ── ทำไมต้องคาลิเบรตก่อนเสมอ ────────────────────────────────────────────
// ค่าที่ MediaPipe คืนมาคือ "ห่างจากหน้ากลาง ๆ ของคนทั่วไปเท่าไหร่" ไม่ใช่
// "ห่างจากหน้าปกติของคุณเท่าไหร่" คนคิ้วสูงโดยธรรมชาติจะได้ browInnerUp ค้างที่
// 0.35 ตลอดเวลา แปลว่าอวาตาร์จะทำหน้าตกใจค้างทั้งวันโดยที่เจ้าตัวไม่ได้ทำอะไรเลย
// จึงต้องเก็บค่าฐาน ~1 วินาทีตอนหน้านิ่ง แล้วลบออกทุกเฟรม
//
// ── ทำไมเครื่องหมายทั้งสามแกนไม่ต้องกลับด้าน (วัดแล้ว ไม่ได้เดา) ──────────
// ระบบพิกัดของ MediaPipe เป็นมือขวา +X ขวา +Y ขึ้น +Z พุ่งออกจากหน้าเข้าหากล้อง
// ซึ่งเป็นระบบเดียวกับ three.js เป๊ะ และตัวละคร VRM ก็หันหน้าไป +Z เหมือนกัน
// (three-vrm หมุนโมเดล VRM 0.x ให้หันไป +Z ตั้งแต่ตอนโหลด ทั้งสองเวอร์ชันจึงเหมือนกัน)
// ไล่ทีละแกน (θ เป็นบวก):
//   Y: R_y หมุน +Z ไปทาง +X → จมูกไปทางขวาของภาพ = คนหันหน้าไปทางซ้ายของตัวเอง
//      ฝั่ง VRM จมูกไป +X = ขวาของคนดู = ซ้ายของตัวละครเอง → **ตรงกัน**
//   X: R_x หมุน +Z ไปทาง -Y → จมูกก้มลง · ฝั่ง VRM ก็ก้มลง → **ตรงกัน**
//   Z: R_z หมุน +Y ไปทาง -X → หัวเอียงไปทางขวาของตัวเอง · VRM เหมือนกัน → **ตรงกัน**
//
// วิธีวัด (ทำซ้ำได้ ไม่ต้องมีกล้องและไม่ต้องมีหน้าใคร):
//   เอา portrait.jpg ของ MediaPipe เองมาแปลงแบบที่**รู้คำตอบล่วงหน้า**แล้วเทียบ
//   1. กลับซ้ายขวา (ctx.scale(-1,1)) → y กับ z ต้องกลับเครื่องหมาย x ต้องเท่าเดิม
//      วัดได้: (.054,.026,.010) → (.061,-.027,-.019) ✓
//   2. หมุนภาพตามเข็ม 0.35 rad (ctx.rotate(+0.35) — canvas แกน Y ชี้ลง ตามเข็มบนจอ
//      = หมุนรอบ +Z ทาง**ลบ**) → z ต้องลดลง 0.35 · วัดได้ .010 → -.338 = -0.348 ✓
//   ยืนยันว่า setFromRotationMatrix(m,'YXZ') บนเมทริกซ์ของ MediaPipe ให้มุมในเฟรม
//   ที่เราคิดไว้จริง ไม่ใช่เฟรมอื่นที่บังเอิญหน้าตาคล้ายกัน
//
// ฝั่ง VRM ยืนยันจากโค้ดที่จูนด้วยตาไว้แล้วใน idle.js: `_nod` เป็นบวกเสมอ
// (บรรทัด 297) แล้วถูกใส่เป็น x ของกระดูก head โดยคอมเมนต์ว่า "the head drops"
// → **x บวก = ก้มลง** ตรงกับที่ไล่ไว้ข้างบน
//
// ที่ยัง**ไม่ได้**พิสูจน์: ความรู้สึกปลายทางกับหน้าคนจริงหน้ากล้องจริง
// ถ้าเจอว่ากลับด้าน แก้ที่ SIGN / MIRROR ข้างล่างที่เดียว
//
// ── กล้องต้องชนะเสียง ──────────────────────────────────────────────────
// เปิดโหมดนี้คือโหมดหุ่นเชิด ปากต้องขยับตามปากจริงของคนเชิด ไม่ใช่ตามคลื่นเสียง
// avatar.js เป็นคนตัดสินใจข้ามการอ่านคลื่นเสียงเมื่อ mocap ทำงานอยู่ ดู _face() ที่นั่น

import * as THREE from 'three';

/** กลับด้านซ้าย-ขวา — ตั้ง true ถ้าเจอว่าอวาตาร์หันสวนทางกับคนเชิด */
const MIRROR = false;

/** เครื่องหมายรายแกน [pitch, yaw, roll] — เหตุผลอยู่ในหัวไฟล์ */
const SIGN = [1, 1, 1];

/** เรเดียนสูงสุดที่ยอมให้หัวหมุนตาม กันคอบิดพิสดารเวลาตรวจจับหลุด */
const HEAD_LIMIT = { x: 0.55, y: 0.75, z: 0.42 };

/** จำนวนเฟรมที่เก็บเป็นค่าฐาน — 30 เฟรม ≈ 1 วินาทีที่ 30fps */
const CALIBRATE_FRAMES = 30;

/** พลาดกี่เฟรมติดกันถึงจะยอมบอกว่า "ไม่เห็นหน้า" — 5 เฟรม ≈ 0.17 วิ */
const MISS_LIMIT = 5;

/**
 * ชื่อ blendshape แบบ ARKit ที่เราสนใจ
 * MediaPipe คืนมา 52 ตัว ใช้จริงไม่ถึงครึ่ง ที่เหลือปล่อยทิ้ง
 */
const WANT = [
    'jawOpen', 'mouthPucker', 'mouthFunnel',
    'mouthSmileLeft', 'mouthSmileRight',
    'mouthStretchLeft', 'mouthStretchRight',
    'mouthFrownLeft', 'mouthFrownRight',
    'eyeBlinkLeft', 'eyeBlinkRight',
    'eyeLookUpLeft', 'eyeLookUpRight',
    'eyeLookDownLeft', 'eyeLookDownRight',
    'eyeLookInLeft', 'eyeLookInRight',
    'eyeLookOutLeft', 'eyeLookOutRight',
    'browInnerUp', 'browDownLeft', 'browDownRight',
    'eyeWideLeft', 'eyeWideRight',
];

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const avg = (a, b) => (a + b) * 0.5;

/**
 * ลบค่าฐานออกแล้วยืดกลับเป็นช่วง 0..1
 *
 * หารด้วย (1 - base) ไม่ใช่ลบเฉย ๆ เพราะถ้าค่าฐานคือ 0.35 การลบอย่างเดียว
 * ทำให้ค่าสูงสุดที่เป็นไปได้เหลือ 0.65 — คนคิ้วสูงเลิกคิ้วสุดแรงยังได้แค่ 65%
 */
const rebase = (raw, base) => clamp01((raw - base) / Math.max(0.15, 1 - base));

export class FaceMocap {
    /** @param {string} base โฟลเดอร์ที่มี vision_bundle.mjs / wasm / .task */
    constructor(base = './vendor/mediapipe/') {
        this.base = base;
        this.active = false;

        /** เจอหน้าในเฟรมล่าสุดไหม — ต่างจาก active ตรงที่คนอาจเดินออกนอกเฟรม */
        this.tracking = false;

        /** 'off' | 'starting' | 'calibrating' | 'live' | 'failed' */
        this.phase = 'off';
        this.error = null;

        /** ความคืบหน้าคาลิเบรต 0..1 — ฝั่ง Flutter เอาไปขึ้นหลอด */
        this.progress = 0;

        /** ค่าที่ทำให้เรียบแล้ว พร้อมเขียนลงหน้า */
        this.blinkL = 0;
        this.blinkR = 0;
        this.look = { up: 0, down: 0, left: 0, right: 0 };
        this.emote = { happy: 0, sad: 0, surprised: 0, angry: 0 };
        this.head = new THREE.Euler(0, 0, 0, 'YXZ');

        this._open = 0;
        this._spread = 0.5;
        this._raw = {};              // ค่าดิบเฟรมล่าสุด หลังลบค่าฐานแล้ว
        this._rawHead = new THREE.Euler(0, 0, 0, 'YXZ');
        this._base = {};             // ค่าฐานจากการคาลิเบรต
        this._baseHead = new THREE.Euler(0, 0, 0, 'YXZ');
        this._samples = [];
        this._lastFrameTime = -1;
        /**
         * เฟรมติด ๆ กันที่หาหน้าไม่เจอ
         *
         * ไม่ประกาศว่า "หลุด" ตั้งแต่เฟรมแรกที่พลาด เพราะการตรวจจับพลาดเฟรมสองเฟรม
         * เป็นเรื่องปกติมาก ถ้ารายงานทันที UI จะกะพริบข้อความ "ไม่เห็นหน้าคุณ"
         * ขึ้น ๆ ลง ๆ ตลอดเวลาที่ใช้งานปกติ
         */
        this._miss = 0;
        this._m = new THREE.Matrix4();
        this._q = new THREE.Quaternion();
        this._e = new THREE.Euler(0, 0, 0, 'YXZ');
    }

    /**
     * ขอกล้อง โหลดโมเดล แล้วเริ่มคาลิเบรต
     *
     * ขอกล้อง**ก่อน**โหลดโมเดล 15MB โดยตั้งใจ: ถ้าผู้ใช้กดปฏิเสธกล้อง
     * จะได้รู้ทันทีโดยไม่ต้องเสียเวลาโหลด wasm ทิ้งเปล่า ๆ
     */
    async start() {
        if (this.active || this.phase === 'starting') return false;
        this.phase = 'starting';
        this.error = null;

        try {
            this.stream = await navigator.mediaDevices.getUserMedia({
                video: {
                    facingMode: 'user',
                    width: { ideal: 640 },
                    height: { ideal: 480 },
                    frameRate: { ideal: 30 },
                },
                audio: false,
            });
        } catch (err) {
            return this._fail('camera', err);
        }

        try {
            await this._loadModel();
        } catch (err) {
            this._releaseCamera();
            return this._fail('model', err);
        }

        // วิดีโอต้องอยู่ในหน้าจริง ๆ ห้าม display:none — เบราว์เซอร์บางตัวหยุด
        // ถอดรหัสเฟรมของวิดีโอที่ถูกซ่อนสนิท แล้ว detectForVideo จะได้เฟรมเดิม
        // ค้างตลอดกาลโดยไม่มี error อะไรเลย · ซ่อนด้วยการดันออกนอกจอแทน
        const v = document.createElement('video');
        v.autoplay = true;
        v.muted = true;
        v.playsInline = true;
        v.setAttribute('playsinline', '');
        v.style.cssText = 'position:fixed;left:-4096px;top:0;width:64px;' +
            'height:48px;opacity:0.01;pointer-events:none';
        v.srcObject = this.stream;
        document.body.appendChild(v);
        this.video = v;

        try {
            await v.play();
        } catch (err) {
            this._teardown();
            return this._fail('video', err);
        }

        this._samples = [];
        this.progress = 0;
        // เริ่มด้วย "ยังเห็นอยู่" เพราะยังไม่เคยอ่านสักเฟรม ยังไม่มีหลักฐานว่าหลุด
        // ถ้าเริ่มด้วย false ผู้ใช้จะเห็น "ไม่เห็นหน้าคุณ" แวบหนึ่งทุกครั้งที่เปิด
        this.tracking = true;
        this._miss = 0;
        this.phase = 'calibrating';
        this.active = true;
        return true;
    }

    async _loadModel() {
        // นำเข้าตอนกดเปิดเท่านั้น ไม่ใช่ตอนโหลดหน้า — bundle 155KB บวก wasm 11MB
        // ไม่ควรถูกจ่ายโดยคนที่ไม่เคยเปิดโหมดนี้เลย
        const { FaceLandmarker } = await import(`${this.base}vision_bundle.mjs`);

        // ประกอบ fileset เองแทน FilesetResolver.forVisionTasks() เพราะตัวนั้น
        // ตรวจว่าเครื่องรองรับ SIMD ไหม แล้วขอไฟล์ nosimd ถ้าไม่รองรับ ซึ่งเรา
        // ไม่ได้แพ็กมาด้วย (อีก 11MB) จะกลายเป็น 404 ที่อ่านไม่ออกว่าเกิดอะไรขึ้น
        const abs = (p) => new URL(this.base + p, location.href).toString();
        const fileset = {
            wasmLoaderPath: abs('wasm/vision_wasm_internal.js'),
            wasmBinaryPath: abs('wasm/vision_wasm_internal.wasm'),
        };

        const opts = {
            baseOptions: {
                modelAssetPath: abs('face_landmarker.task'),
                delegate: 'GPU',
            },
            runningMode: 'VIDEO',
            numFaces: 1,
            outputFaceBlendshapes: true,
            outputFacialTransformationMatrixes: true,
        };

        try {
            this.landmarker = await FaceLandmarker.createFromOptions(fileset, opts);
        } catch (err) {
            // GPU delegate ล้มบนเครื่องที่ไดรเวอร์มีปัญหา — CPU ช้ากว่าแต่ยังใช้ได้
            // ดีกว่าปิดฟีเจอร์ทิ้งทั้งอัน
            opts.baseOptions.delegate = 'CPU';
            this.landmarker = await FaceLandmarker.createFromOptions(fileset, opts);
        }
    }

    /**
     * อ่านกล้องหนึ่งเฟรมแล้วทำให้ค่าเรียบ เรียกทุกเฟรมจากลูปของ avatar.js
     * @param {number} dt วินาทีนับจากครั้งก่อน
     * @param {number} nowMs เวลาแบบ monotonic สำหรับ MediaPipe
     */
    update(dt, nowMs) {
        if (this.active) this._read(nowMs);
        this._smooth(dt);
    }

    _read(nowMs) {
        const v = this.video;
        if (!this.landmarker || !v || v.readyState < 2) return;

        // เฟรมเดิมที่ยังไม่ขยับส่งซ้ำไม่ได้ — MediaPipe บังคับว่า timestamp ต้อง
        // เพิ่มขึ้นเรื่อย ๆ ถ้าส่งเฟรมเดิมซ้ำมันจะโยน error ทิ้งทั้งลูป
        if (v.currentTime === this._lastFrameTime) return;
        this._lastFrameTime = v.currentTime;

        let res;
        try {
            res = this.landmarker.detectForVideo(v, nowMs);
        } catch (err) {
            this._fail('detect', err);
            return;
        }

        const shapes = res?.faceBlendshapes?.[0]?.categories;
        if (!shapes || !shapes.length) {
            // คนเดินออกนอกเฟรม — ไม่ใช่ error ปล่อยให้หน้าจางกลับท่านิ่งเอง
            if (++this._miss >= MISS_LIMIT) this.tracking = false;
            for (const k of WANT) this._raw[k] = 0;
            this._rawHead.set(0, 0, 0, 'YXZ');
            return;
        }
        this._miss = 0;
        this.tracking = true;

        const now = {};
        for (const c of shapes) {
            if (WANT.includes(c.categoryName)) now[c.categoryName] = c.score;
        }

        const mtx = res.facialTransformationMatrixes?.[0]?.data;
        const headNow = new THREE.Euler(0, 0, 0, 'YXZ');
        if (mtx && mtx.length === 16) {
            this._m.fromArray(mtx);
            headNow.setFromRotationMatrix(this._m, 'YXZ');
        }

        if (this.phase === 'calibrating') {
            this._samples.push({ shapes: now, head: headNow });
            this.progress = this._samples.length / CALIBRATE_FRAMES;
            if (this._samples.length >= CALIBRATE_FRAMES) this._finishCalibration();
            return;
        }

        for (const k of WANT) this._raw[k] = rebase(now[k] ?? 0, this._base[k] ?? 0);
        this._rawHead.set(
            headNow.x - this._baseHead.x,
            headNow.y - this._baseHead.y,
            headNow.z - this._baseHead.z,
            'YXZ',
        );
    }

    _finishCalibration() {
        const n = this._samples.length;
        for (const k of WANT) {
            let s = 0;
            for (const smp of this._samples) s += smp.shapes[k] ?? 0;
            this._base[k] = s / n;
        }
        let hx = 0, hy = 0, hz = 0;
        for (const smp of this._samples) {
            hx += smp.head.x; hy += smp.head.y; hz += smp.head.z;
        }
        this._baseHead.set(hx / n, hy / n, hz / n, 'YXZ');

        // การกะพริบตาไม่เอาค่าฐาน: คนคาลิเบรตอาจเผลอกะพริบพอดี แล้วอวาตาร์จะ
        // หลับตาไม่ลงไปตลอดทั้งเซสชัน · ตาที่เปิดปกติค่าฐานเป็น 0 อยู่แล้ว
        this._base.eyeBlinkLeft = 0;
        this._base.eyeBlinkRight = 0;

        this._samples = [];
        this.progress = 1;
        this.phase = 'live';
    }

    /**
     * ทำให้ค่าเรียบ — กล้องส่งค่ากระตุกทุกเฟรม เขียนลงหน้าดิบ ๆ แล้วหน้าจะสั่น
     *
     * ปากใช้จังหวะเดียวกับ lipsync.js คือ**เปิดเร็ว ปิดช้ากว่า** เพราะปากคนเป็นแบบนั้น
     * ส่วนหัวใช้เรตเดียวช้า ๆ เพราะคอไม่ได้กระตุกเป็นพยางค์
     */
    _smooth(dt) {
        const ease = (rate) => 1 - Math.exp(-rate * dt);
        const live = this.active && this.phase === 'live' && this.tracking;
        const r = this._raw;
        const g = (k) => (live ? (r[k] ?? 0) : 0);

        // ── ปาก ────────────────────────────────────────────
        // อ้าปากมาจาก jawOpen ตรง ๆ · รูปปากมาจากแกน "แบะ↔จู๋" เดียวกับที่
        // lipsync.js ใช้ จะได้ส่งเข้าฟังก์ชัน shape() ตัวเดิมได้เลย
        const open = clamp01(g('jawOpen') * 1.35);
        const wide = avg(g('mouthSmileLeft'), g('mouthSmileRight'))
                   + avg(g('mouthStretchLeft'), g('mouthStretchRight')) * 0.6;
        const round = g('mouthPucker') + g('mouthFunnel') * 0.7;
        const spread = clamp01(0.5 + wide * 0.85 - round * 1.15);

        this._open += (open - this._open) * ease(open > this._open ? 110 : 26);
        this._spread += (spread - this._spread) * ease(22);

        // ── ตา ─────────────────────────────────────────────
        const bl = clamp01(g('eyeBlinkLeft') * 1.15);
        const br = clamp01(g('eyeBlinkRight') * 1.15);
        this.blinkL += (bl - this.blinkL) * ease(bl > this.blinkL ? 95 : 34);
        this.blinkR += (br - this.blinkR) * ease(br > this.blinkR ? 95 : 34);

        // ตามอง — ARKit แยก In/Out ตามข้างของตา ต้องรวมเป็นซ้าย/ขวาของ**คน**ก่อน
        // ตาซ้ายมองออกนอก = มองไปทางซ้ายของตัวเอง · ตาขวามองเข้าใน = ทางซ้ายเหมือนกัน
        const lookL = avg(g('eyeLookOutLeft'), g('eyeLookInRight'));
        const lookR = avg(g('eyeLookInLeft'), g('eyeLookOutRight'));
        const lookU = avg(g('eyeLookUpLeft'), g('eyeLookUpRight'));
        const lookD = avg(g('eyeLookDownLeft'), g('eyeLookDownRight'));
        const k = ease(20);
        this.look.left += ((MIRROR ? lookR : lookL) - this.look.left) * k;
        this.look.right += ((MIRROR ? lookL : lookR) - this.look.right) * k;
        this.look.up += (lookU - this.look.up) * k;
        this.look.down += (lookD - this.look.down) * k;

        // ── อารมณ์ ─────────────────────────────────────────
        // ทดไว้เยอะ: expression พวกนี้บนหน้า VRoid แรงมาก ใส่เต็มค่าจากกล้อง
        // แล้วมันจะกลืนรูปปากจนพูดไม่รู้เรื่อง
        const smile = avg(g('mouthSmileLeft'), g('mouthSmileRight'));
        const frown = avg(g('mouthFrownLeft'), g('mouthFrownRight'));
        const browUp = g('browInnerUp');
        const browDn = avg(g('browDownLeft'), g('browDownRight'));
        const eyeWide = avg(g('eyeWideLeft'), g('eyeWideRight'));
        const ke = ease(9);
        this.emote.happy += (clamp01(smile * 0.75) - this.emote.happy) * ke;
        this.emote.sad += (clamp01(frown * 0.70) - this.emote.sad) * ke;
        this.emote.surprised +=
            (clamp01((browUp * 0.55 + eyeWide * 0.45) * 0.8) - this.emote.surprised) * ke;
        this.emote.angry += (clamp01(browDn * 0.60) - this.emote.angry) * ke;

        // ── หัว ────────────────────────────────────────────
        const flip = MIRROR ? -1 : 1;
        const hx = clamp(this._rawHead.x * SIGN[0], -HEAD_LIMIT.x, HEAD_LIMIT.x);
        const hy = clamp(this._rawHead.y * SIGN[1] * flip, -HEAD_LIMIT.y, HEAD_LIMIT.y);
        const hz = clamp(this._rawHead.z * SIGN[2] * flip, -HEAD_LIMIT.z, HEAD_LIMIT.z);
        const kh = ease(live ? 13 : 5);
        this.head.set(
            this.head.x + ((live ? hx : 0) - this.head.x) * kh,
            this.head.y + ((live ? hy : 0) - this.head.y) * kh,
            this.head.z + ((live ? hz : 0) - this.head.z) * kh,
            'YXZ',
        );
    }

    /**
     * รูปปากปัจจุบันบนแกน (อ้า, แบะ) — ให้ผู้เรียกส่งต่อเข้า LipSync.shape()
     * ที่เป็นฟังก์ชันบริสุทธิ์ตัวเดิม จะได้มีโมเดลปากชุดเดียวทั้งแอป
     */
    mouth() {
        return { open: this._open, spread: this._spread };
    }

    /**
     * เขียนท่าหัวทับกระดูก คอ+หัว
     *
     * แบ่งสองข้อเหมือน idle.js เพราะคอคนหักที่สองจุด ยัดลงข้อเดียวจะได้คอ
     * ผิดรูปเวลาหันแรง ๆ · เรียก**หลัง** idle.apply() เท่านั้น ไม่งั้นถูกทับ
     */
    applyHead(vrm, weight = 1) {
        if (!vrm || weight <= 0.001) return;
        const h = vrm.humanoid;
        if (!h) return;

        const neck = h.getNormalizedBoneNode('neck');
        const head = h.getNormalizedBoneNode('head');
        if (neck) this._blend(neck, 0.40, weight);
        if (head) this._blend(head, 0.60, weight);
    }

    _blend(node, share, weight) {
        this._e.set(this.head.x * share, this.head.y * share, this.head.z * share, 'YXZ');
        // คูณเข้ากับท่าที่ idle วางไว้ ไม่ใช่เขียนทับ — ท่ายืนพื้นฐานกับการหายใจ
        // ยังอยู่ ส่วนที่กล้องสั่งเป็นการหมุน**เพิ่ม**จากตรงนั้น
        this._q.setFromEuler(this._e).premultiply(node.quaternion);
        node.quaternion.slerp(this._q, weight);
    }

    /** ปิดกล้อง คืนทรัพยากร แล้วปล่อยให้หน้าจางกลับเอง */
    stop() {
        this._teardown();
        this.active = false;
        this.tracking = false;
        this.phase = 'off';
        this.progress = 0;
        for (const k of WANT) this._raw[k] = 0;
        this._rawHead.set(0, 0, 0, 'YXZ');
    }

    /** เริ่มเก็บค่าฐานใหม่ — ใช้ตอนเปลี่ยนคนเชิด หรือย้ายไปนั่งอีกที่ */
    recalibrate() {
        if (!this.active) return false;
        this._samples = [];
        this.progress = 0;
        this._miss = 0;
        this.tracking = true;
        this.phase = 'calibrating';
        return true;
    }

    /** สถานะย่อ ๆ ให้ฝั่ง Flutter อ่าน */
    status() {
        return {
            active: this.active,
            tracking: this.tracking,
            phase: this.phase,
            progress: this.progress,
            error: this.error,
        };
    }

    _releaseCamera() {
        try {
            this.stream?.getTracks().forEach((t) => t.stop());
        } catch { /* แทร็กปิดไปแล้ว ไม่ใช่เรื่องต้องรายงาน */ }
        this.stream = null;
    }

    _teardown() {
        this._releaseCamera();
        try {
            this.landmarker?.close();
        } catch { /* ปิดซ้ำ ไม่เป็นไร */ }
        this.landmarker = null;
        if (this.video) {
            this.video.srcObject = null;
            this.video.remove();
            this.video = null;
        }
        this._lastFrameTime = -1;
    }

    _fail(where, err) {
        this.phase = 'failed';
        this.active = false;
        this.error = `${where}: ${err?.message ?? err}`;
        return false;
    }

    dispose() {
        this.stop();
    }
}
