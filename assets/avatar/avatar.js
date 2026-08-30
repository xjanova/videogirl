// avatar.js — Mind as a whole body. Replaces AssistantFace, and keeps its
// public shape (`speak`, `setMood`, `resize`, `dispose`) so the window that
// hosts her does not have to care which one it got.
//
// WHAT THIS FILE ACTUALLY DOES is arbitrate. Five things want to write her
// bones and her face every frame — the animation mixer, the procedural idle,
// the lip sync, the look-at, and the spring bones — and the only reason it
// works is that they run in a fixed order with explicit weights. Get the order
// wrong and one silently erases another with no error to show for it:
//
//   1. mixer      the clip, if any, writes every bone it owns
//   2. idle       breathing / fidget / nods, SLERPED over the top by a weight
//                 that drops to a whisper while a clip is playing
//   3. expressions viseme weights, then mood, then blink
//   4. vrm.update propagates the normalized rig to the real one, runs look-at
//                 and the spring bones LAST, so hair reacts to the final pose
//
// WHY THE CAMERA CHANGES SHOT. A fixed wide shot wastes the expression work —
// while she talks her face is forty pixels tall. A fixed close shot throws away
// the body. So the shot follows the state: bust while speaking, full while
// idle. See framing.js for why the distances are measured rather than typed.

import * as THREE from 'three';
import { GLTFLoader } from './vendor/three/jsm/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';
import { Motion } from './motion.js';
import { Idle } from './idle.js';
import { LipSync } from './lipsync.js';
import { Framing } from './framing.js';
import { FaceMocap } from './mocap.js';

/**
 * Mood -> the VRM expression that carries it, and how much of it.
 *
 * Two moods share an expression on purpose — `pleased` is `happy` turned down.
 * That sharing is also why the expressions are driven from a UNIQUE set below
 * rather than by iterating this table: iterating it sets `happy` twice, and the
 * second pass (for whichever mood is not current) drives it straight back to
 * zero. The face just never smiled, with nothing to show why.
 */
const MOOD_EXPRESSION = {
    neutral:   null,
    happy:     ['happy', 1.00],
    pleased:   ['happy', 0.45],
    concerned: ['sad', 0.55],
    thinking:  null,
    // ถูกทิ้งไว้นานจนเบื่อ · ไม่บังคับสีหน้า คลิปยืนเป็นตัวเล่าเอง
    waiting:   null,
    // กำลังมีสายอยู่ · คลิปถือโทรศัพท์เล่าเอง ไม่ต้องบังคับสีหน้า
    calling:   null,
    sorry:     ['sad', 0.85],
    alert:     ['surprised', 0.80],
    angry:     ['angry', 0.85],
};

/** Every expression any mood can use, each named once. */
const MOOD_EXPRS = [...new Set(
    Object.values(MOOD_EXPRESSION).filter(Boolean).map(([e]) => e))];

/**
 * เงียบกี่วินาทีถึงจะถือว่าถูกทิ้งไว้
 *
 * สองนาที · สั้นกว่านี้เธอจะทำท่าเบื่อใส่คนที่แค่หยุดพิมพ์ไปคิดแป๊บเดียว
 */
const QUIET_UNTIL_WAITING = 120;

/** The gaze expressions. Only the camera writes these, so only it cleans up. */
const LOOK_EXPRS = ['lookUp', 'lookDown', 'lookLeft', 'lookRight'];

export class Avatar {
    constructor(host, opts = {}) {
        this.host = host;
        this.base = opts.base ?? './avatar/';
        this.model = opts.model ?? 'minde.vrm';
        this.mood = 'neutral';
        this.speaking = false;
        this.ready = false;

        /**
         * เรียกทุกครั้งที่ความคืบหน้าเปลี่ยน — ผู้ที่ฝังหน้านี้ตั้งเอง
         *
         * ตัวเลขที่ส่งออกไปคือ**ของจริง** จาก byte ที่โหลดมาแล้ว ไม่ใช่แถบ
         * ที่วิ่งเองตามเวลา · แถบปลอมบอกอะไรผู้ใช้ไม่ได้เลยเวลามันค้างจริง
         * @type {?(p:number)=>void}
         */
        this.onProgress = null;

        /** เรียกเมื่อ**ตัวเธอขึ้นจอแล้ว** ซึ่งมาก่อนคลิปท่าทางโหลดเสร็จ */
        this.onVisible = null;

        /** เรียกครั้งเดียวเมื่อลูปเรนเดอร์ล้ม — ดู [_loop] */
        this.onLoopError = null;
        this._loopDead = false;

        /** เงียบมากี่วินาทีแล้ว — ดู [_frame] */
        this._quiet = 0;
        this._autoWait = false;

        const w = host.clientWidth || 320, h = host.clientHeight || 300;
        this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
        this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
        // updateStyle ON: with it off the canvas gets no CSS size and lays out
        // at its BUFFER size, so on a HiDPI screen she bursts out of the panel
        // and how big she looks depends on the monitor.
        this.renderer.setSize(w, h);
        host.appendChild(this.renderer.domElement);

        this.scene = new THREE.Scene();
        this.camera = new THREE.PerspectiveCamera(28, w / h, 0.1, 40);
        // Toon shading needs a key light with a direction or she reads flat.
        const key = new THREE.DirectionalLight(0xffffff, 2.1);
        key.position.set(1.2, 2.0, 2.4);
        this.scene.add(key, new THREE.AmbientLight(0xbfd4ff, 1.15));

        this.lip = new LipSync();
        // The camera puppet. Nothing is loaded and no permission is asked until
        // someone calls `start()` — the wasm alone is 11MB and most sessions
        // never turn this on.
        this.mocap = new FaceMocap('./vendor/mediapipe/');
        this.clock = new THREE.Clock();
        this._loop = this._loop.bind(this);
        this._t = 0;

        this.loaded = this._load();
    }

    async _load() {
        const loader = new GLTFLoader();
        loader.register((p) => new VRMLoaderPlugin(p));
        // VRM 33MB คือของที่หนักที่สุดในการเปิดแอป กินสัดส่วนใหญ่ของแถบ
        const gltf = await loader.loadAsync(this.base + this.model, (e) => {
            if (e && e.lengthComputable && e.total > 0) {
                this.onProgress?.((e.loaded / e.total) * 0.85);
            }
        });
        const vrm = gltf.userData.vrm;
        // Drop vertices nothing references, and merge the per-primitive
        // skeletons VRoid emits — 20-odd draw calls become a handful.
        for (const fn of ['removeUnnecessaryVertices', 'combineSkeletons'])
            if (typeof VRMUtils[fn] === 'function') { try { VRMUtils[fn](gltf.scene); } catch {} }
        this.vrm = vrm;
        this.scene.add(vrm.scene);

        // Whether this model carries per-eye blinks. Probed ONCE, here, because
        // `setValue` on a name the model does not have is a silent no-op: drive
        // `blinkLeft` on a model that only has `blink` and she simply never
        // blinks again, with nothing anywhere to say why.
        const em = vrm.expressionManager;
        this._blinkLR = !!(em?.getExpression?.('blinkLeft')
                        && em?.getExpression?.('blinkRight'));

        // `relaxed` เป็นรอยยิ้มที่นุ่มกว่า `happy` ของ VRoid ซึ่งหลับตาแรง
        // แต่ไม่ใช่ทุกรุ่นที่มี — ต้อง probe ครั้งเดียวตอนโหลด เพราะ setValue
        // ชื่อที่ไม่มีคือ no-op เงียบ ๆ แล้วเธอจะไม่ยิ้มเลยโดยไม่มีอะไรบอก
        this._hasRelaxed = !!em?.getExpression?.('relaxed');

        // 🔴 สายตาของรุ่นนี้ **ไม่ได้ทำด้วย expression**
        //
        // probe แล้วพบว่า lookUp/lookDown/lookLeft/lookRight ไม่มีในโมเดล
        // (มีแค่ happy angry sad relaxed surprised + วิเซม + blink)
        // การ setValue ชื่อที่ไม่มีคือ **no-op เงียบ ๆ** โหมดเชิดหุ่นจึงสั่ง
        // สายตาไปแล้วไม่มีอะไรเกิดขึ้นเลย โดยไม่มี error ที่ไหนบอก
        //
        // ทางที่ถูกของ VRM คือ `vrm.lookAt` ซึ่งขยับลูกตาจริงตามเป้าที่ให้
        // เตรียมเป้าไว้ที่นี่ ใช้เฉพาะตอนเชิดหุ่น
        this._hasLookExpr = !!em?.getExpression?.('lookUp');
        this._gaze = new THREE.Object3D();
        this.scene.add(this._gaze);
        this._gazeBase = new THREE.Vector3();

        this.idle = new Idle(vrm);
        this.framing = new Framing(this.camera, vrm);
        this.motion = new Motion(vrm, this.base);

        // She is on screen and breathing before the clips finish arriving:
        // twenty FBX files parse on the main thread and take a couple of
        // seconds, and a blank panel for those seconds is worse than a still
        // one.
        this.ready = true;
        this._raf = requestAnimationFrame(this._loop);

        // ตัวเธออยู่บนจอแล้วตรงนี้ — คลิปท่าทางยังทยอยมาอยู่ แต่คนดูเห็นเธอแล้ว
        // นี่คือจังหวะที่หน้าเปิดแอปควรหลบให้ ไม่ใช่รอจนคลิปครบ
        this.onProgress?.(0.85);
        this.onVisible?.();

        await this.motion.load((done, total) => {
            this.onProgress?.(0.85 + 0.15 * (total > 0 ? done / total : 1));
        });
        this.onProgress?.(1);
        this._applyMood();
        return this;
    }

    /** @param {string} m a key of MOOD_EXPRESSION */
    setMood(m) {
        // มีคนสั่งอารมณ์มา = มีอะไรเกิดขึ้น = ยังไม่ถูกทิ้ง
        this._quiet = 0;
        this._autoWait = false;
        this.mood = m in MOOD_EXPRESSION ? m : 'neutral';

        // ตอนคุยโทรศัพท์ปากต้องขยับตลอด แต่**ไม่มีเสียงให้วิเคราะห์**
        // เสียงในสายแตะไม่ได้ทั้งขาเข้าและขาออก · ถ้าไม่เปิดโหมดนี้
        // เธอจะยกโทรศัพท์ขึ้นมาแล้วปากนิ่งสนิทตลอดสาย
        this.lip.babble = this.mood === 'calling';

        this._applyMood();
        return this;
    }

    _applyMood() {
        this.motion?.setMood(this.mood);
    }

    /**
     * Say something. Drives the visemes from the audio, pushes in to the bust
     * shot, holds the gesture scheduler off, and puts everything back after.
     */
    async speak(url) {
        this.speaking = true;
        this._quiet = 0;
        if (this._autoWait) { this._autoWait = false; this.setMood('neutral'); }
        this.motion?.setBusy(true);
        this.motion?.setTalking(true);
        this.framing?.set('bust');
        try {
            return await this.lip.play(url);
        } finally {
            this.speaking = false;
            this.motion?.setBusy(false);
            this.motion?.setTalking(false);
            this.framing?.set('full');
        }
    }

    stop() {
        this.lip.stop();
        this.speaking = false;
        this.motion?.setBusy(false);
        this.motion?.setTalking(false);
        this.framing?.set('full');
    }

    /** Sit down / stand up, if the clips for it are present. */
    sit() { return this.motion?.sit() ?? false; }
    stand() { return this.motion?.stand() ?? false; }

    // ── the camera puppet ────────────────────────────────────────────────
    //
    // `live` and not merely `active` on purpose: while the baseline is being
    // collected the puppeteer is holding still ON PURPOSE, and a face that
    // started copying them mid-calibration would bake that copy into the
    // baseline it is in the middle of measuring.
    get puppet() {
        return this.mocap.active && this.mocap.phase === 'live';
    }

    async startMocap() {
        await this.mocap.start();
        return this.mocap.status();
    }

    stopMocap() {
        this.mocap.stop();
        return this.mocap.status();
    }

    /** Re-measure the resting face — new puppeteer, or the same one moved. */
    recalibrate() {
        this.mocap.recalibrate();
        return this.mocap.status();
    }

    mocapStatus() { return this.mocap.status(); }

    /**
     * 🔴 **ข้อผิดพลาดในลูปนี้เคยเงียบสนิทมาแล้ว**
     *
     * `requestAnimationFrame` ถูกต่อคิวเป็นบรรทัดแรกเสมอ (ตั้งใจ — ลูปต้อง
     * ไม่ตายเพราะเฟรมเดียวสะดุด) แต่ผลข้างเคียงคือ throw ทุกเฟรมก็ยังต่อคิวต่อ
     * ได้เรื่อย ๆ · เธอหายไปทั้งตัว โดยที่แอปยังคิดว่าทุกอย่างปกติ เพราะ
     * `visible` ยิงไปแล้วตั้งแต่ก่อนหน้า มีแต่ใน logcat ที่มีร่องรอย
     *
     * จึงต้องดักไว้ และ**รายงานออกไปครั้งเดียว** ให้ฝั่งแอปรู้ว่าเวทีตายแล้ว
     * ครั้งเดียวเพราะถ้ารายงานทุกเฟรมคือยิงข้ามสะพาน 60 ครั้งต่อวินาที
     */
    _loop() {
        this._raf = requestAnimationFrame(this._loop);
        try {
            this._frame();
        } catch (err) {
            if (this._loopDead) return;
            this._loopDead = true;
            console.error('avatar: ลูปเรนเดอร์ล้ม', err);
            this.onLoopError?.(String(err?.stack ?? err?.message ?? err));
        }
    }

    _frame() {
        const dt = Math.min(0.1, this.clock.getDelta());
        this._t += dt;
        const vrm = this.vrm;
        if (!vrm) return;

        // ถูกทิ้งไว้นานจนเบื่อ
        //
        // clips.json มีคลิป mood 'waiting' มาตั้งแต่ต้น แต่**ไม่มีอะไรในแอป
        // ตั้งอารมณ์นี้เลย** และ setMood() ก็ปัดค่าที่ไม่รู้จักกลับเป็น neutral
        // คลิปที่โหลดมาจึงนอนนิ่งอยู่บนดิสก์โดยไม่มีอะไรบอกสักอย่าง
        //
        // จับเวลาที่นี่ ไม่ใช่ฝั่ง Flutter เพราะที่นี่คือที่เดียวที่รู้แน่ว่า
        // เธอไม่ได้พูดและไม่มีใครสั่งอะไรมา
        this._quiet += dt;
        if (!this._autoWait && !this.speaking
            && this.mood === 'neutral' && this._quiet > QUIET_UNTIL_WAITING) {
            this.setMood('waiting');
            this._autoWait = true;   // setMood ล้างธงนี้ ต้องตั้งกลับหลังเรียก
        }

        // 1 — the clip writes the bones it owns.
        this.motion?.update(dt, performance.now());

        // 2 — the procedural layer rides over it. Full weight when no clip has
        // the body; a whisper of breathing when one does, so a canned loop
        // still looks like it is being performed by something that breathes.
        const w = this.motion?.ready ? 0.18 : 1;
        // Mixamo's standing idles are braced, knees bent, weight forward. While
        // she is on her FEET that stance is pulled back toward standing; while
        // she is sitting or mid-transition it is left alone, or the correction
        // would stand her up through the chair.
        const onFeet = !this.motion?.ready
            || ['idle', 'gesture'].includes(this.motion.current?.meta.role ?? 'idle');
        // Her arms are held clear of the skirt only while she is idling on her
        // feet. During a gesture they belong to the clip — holding them out
        // through a wave would flatten it back into a stand.
        //
        // 🔴 คลิปคุยโทรศัพท์เป็น role 'idle' (มันคือท่ายืนที่วนอยู่) ซึ่งแปลว่า
        // ชั้น procedural คิดว่าแขนเป็นของมัน แล้วดึงแขนลงข้างตัวทับคลิป
        // ผลคือเธอ "คุยโทรศัพท์" โดยไม่ได้ยกโทรศัพท์เลย — คลิปเล่นอยู่จริง
        // ทุกอย่างดูเหมือนทำงาน แต่ภาพที่ออกมาผิด
        //
        // เห็นได้ด้วยตาเท่านั้น ตัวเลขบอกว่าคลิปถูกเล่นอยู่ทุกประการ
        const onPhone = this.mood === 'calling';
        const armsFree = onPhone
            || !!this.motion?.gesture
            || (this.motion?.current?.meta.role ?? 'idle') !== 'idle';
        this.lip.update(dt);
        this.mocap.update(dt, performance.now());
        this.idle.apply(this._t, w, this.lip.speaking ? this.lip.level : 0, dt,
                        onPhone ? 0 : (onFeet ? 0.82 : 0), armsFree ? 0 : 0.75);

        // 3 — face.
        this._face(dt);

        // 3b — the camera, if someone is puppeteering. AFTER idle, which owns
        // the neck and the head every frame; before vrm.update, so the spring
        // bones still get the final pose and her hair follows the real turn.
        if (this.puppet) this.mocap.applyHead(vrm, 0.9);

        // 4 — propagate, look-at, spring bones.
        vrm.update(dt);

        this.framing?.update(dt, this.speaking ? 0.65 : 1.1);
        this.renderer.render(this.scene, this.camera);
    }

    /**
     * Visemes first, then the mood underneath them, then the blink last so it
     * wins: a blink that loses to an expression is a character who stares
     * through whole sentences.
     *
     * Separate from the render loop so it can be stepped and checked without
     * waiting on requestAnimationFrame, which the host pane throttles to a
     * crawl whenever it is not visible — every timing-based check of this has
     * to be synchronous or it measures the scheduler instead of the code.
     */
    _face(dt = 1 / 60) {
        const em = this.vrm?.expressionManager;
        if (!em) return;
        const k = 1 - Math.exp(-5.2 * dt);
        const ease = (name, want) => {
            const cur = em.getValue(name) ?? 0;
            em.setValue(name, cur + (want - cur) * k);
        };

        if (this.puppet) {
            // THE CAMERA WINS, WHOLE FACE. This is a puppet mode: her mouth
            // belongs to the mouth in front of the lens, not to the waveform,
            // and her mood belongs to that face too. Letting the audio keep the
            // visemes here would look like a dub — the lips would move while
            // she is silent and stay shut while the puppeteer talks.
            //
            // Note this feeds the SAME `shape()` the audio path uses. There is
            // one mouth model in this app, and only where its two numbers come
            // from changes.
            const m = this.mocap.mouth();
            this.lip.shape(m.open, m.spread);
            this.lip.applyTo(this.vrm);

            const e = this.mocap.emote;
            ease('happy', e.happy);
            ease('sad', e.sad);
            ease('angry', e.angry);
            ease('surprised', e.surprised);

            this._aimEyes(this.mocap.look);

            if (this._blinkLR) {
                em.setValue('blinkLeft', this.mocap.blinkL);
                em.setValue('blinkRight', this.mocap.blinkR);
                // Zeroed, or a model carrying both would blink twice over and
                // her eyes would never open again.
                em.setValue('blink', 0);
            } else {
                em.setValue('blink', Math.max(this.mocap.blinkL, this.mocap.blinkR));
            }
            return;
        }

        this.lip.applyTo(this.vrm);
        const [wantExpr, wantAmt] = MOOD_EXPRESSION[this.mood] ?? [null, 0];
        // A VRoid `happy` closes the eyes and reshapes the mouth, so at full
        // weight it simply eats the visemes. Held back while she is talking —
        // the mood stays legible and the words still land.
        const cap = this.speaking ? 0.45 : 1;

        // สีหน้าตอนอยู่เฉย ๆ — ร่างกายมี fidget กับ gesture อยู่แล้ว
        // แต่หน้าเคยนิ่งสนิทเหลือแค่กะพริบตา ซึ่งอ่านว่าหุ่น ไม่ใช่คน
        //
        // ทับเฉพาะตอน mood เป็น neutral · ถ้าเจ้าของตั้งอารมณ์ไว้แล้ว
        // อารมณ์นั้นต้องชนะ ไม่ใช่โดนรอยยิ้มสุ่ม ๆ กลบ
        const warmOn = (this.mood === 'neutral' || this.mood === 'waiting')
            && !this.speaking;

        const warmName = !warmOn
            ? null
            : this.idle.warmthName === 'relaxed' && this._hasRelaxed
                ? 'relaxed'
                : 'happy';
        const warmAmt = warmOn ? this.idle.warmth : 0;

        for (const expr of MOOD_EXPRS) {
            const cur = em.getValue(expr) ?? 0;
            let want = expr === wantExpr ? wantAmt * cap : 0;
            if (expr === warmName) want = Math.max(want, warmAmt);
            em.setValue(expr, cur + (want - cur) * k);
        }

        // `relaxed` ไม่ได้อยู่ใน MOOD_EXPRS จึงไม่มีใครไล่มันกลับศูนย์ให้
        // ต้องเขียนเองทุกเฟรม ไม่งั้นค้างอยู่ตอนเลิกยิ้ม
        if (this._hasRelaxed) {
            const cur = em.getValue('relaxed') ?? 0;
            const want = warmName === 'relaxed' ? warmAmt : 0;
            em.setValue('relaxed', cur + (want - cur) * k);
        }

        em.setValue('blink', this.idle.blink);

        // เลิกเชิดหุ่นแล้ว ปล่อยลูกตากลับไปมองตรง
        const look = this.vrm?.lookAt;
        if (look && look.target === this._gaze) look.target = null;

        // The camera's leftovers, walked back to zero. Nothing else in the app
        // writes these four, so switching the camera off while looking away
        // would otherwise leave her eyes stuck in that corner for the rest of
        // the session — a state with no error, no log, and no way back short of
        // reloading the page.
        for (const n of LOOK_EXPRS) ease(n, 0);
        if (this._blinkLR) { ease('blinkLeft', 0); ease('blinkRight', 0); }
    }

    /**
     * เล็งลูกตาไปตามที่กล้องเห็น
     *
     * ใช้ `vrm.lookAt` ไม่ใช่ expression เพราะโมเดลจำนวนมาก (รวมรุ่นที่ใช้อยู่)
     * ไม่มี expression สายตา · lookAt ขยับลูกตาจริงและทำงานกับทุกรุ่น
     *
     * รุ่นที่มี expression ด้วยก็ยังเซ็ตให้ เผื่อรุ่นนั้นทำสายตาด้วยวิธีนั้น
     */
    _aimEyes(l) {
        const vrm = this.vrm;
        const em = vrm?.expressionManager;
        if (!vrm) return;

        if (this._hasLookExpr && em) {
            em.setValue('lookUp', l.up);
            em.setValue('lookDown', l.down);
            em.setValue('lookLeft', l.left);
            em.setValue('lookRight', l.right);
        }

        const head = vrm.humanoid?.getNormalizedBoneNode('head');
        if (!vrm.lookAt || !head) return;

        head.getWorldPosition(this._gazeBase);
        // หนึ่งเมตรข้างหน้าเธอ แล้วเลื่อนข้าง/ขึ้นลงตามที่มองอยู่
        // ตัวคูณเล็ก เพราะลูกตาคนกลอกได้ไม่กี่องศาก่อนจะดูเป็นการ์ตูน
        this._gaze.position
            .set((l.right - l.left) * 0.5, (l.up - l.down) * 0.35, 1)
            .applyQuaternion(vrm.scene.quaternion)
            .add(this._gazeBase);
        vrm.lookAt.target = this._gaze;
    }

    resize(w, h) {
        if (!(w > 0) || !(h > 0)) return;
        if (w === this._w && h === this._h) return;
        this._w = w;
        this._h = h;
        this.camera.aspect = w / h;
        this.camera.updateProjectionMatrix();
        this.renderer.setSize(w, h);
    }

    /**
     * Keep the canvas the size of the element it lives in, forever.
     *
     * 🔴 WHY THIS EXISTS. The constructor reads `host.clientWidth`, and inside a
     * freshly created WebView that is 0 — layout has not run yet — so it fell
     * back to 320. The only thing that ever corrected it was a `resize` event
     * on `window`, which on a phone simply never fires. The canvas therefore
     * stayed 320 CSS px wide inside a ~393 CSS px stage FOR THE WHOLE SESSION:
     * left-aligned, so she rendered about 10% of the screen width left of
     * centre, and smaller than intended. Measured on device: her centre sat
     * 104px left of the screen centre on a 1080px screen.
     *
     * Nothing reported an error. The picture just quietly had the wrong shape.
     */
    watchSize(host) {
        this.resize(host.clientWidth, host.clientHeight);
        if (typeof ResizeObserver !== 'function') return;
        this._ro?.disconnect();
        this._ro = new ResizeObserver(() =>
            this.resize(host.clientWidth, host.clientHeight));
        this._ro.observe(host);
    }

    dispose() {
        this._ro?.disconnect();
        cancelAnimationFrame(this._raf);
        this.lip.dispose();
        // Releases the camera. Skipping this leaves the recording light on
        // after she is gone, which reads as spyware and is fair enough.
        this.mocap.dispose();
        this.motion?.dispose();
        if (this.vrm) VRMUtils.deepDispose?.(this.vrm.scene);
        this.renderer.dispose();
        this.renderer.domElement.remove();
    }
}
