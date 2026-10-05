// lipsync.js — her mouth, driven from the audio she is playing.
//
// WHY THIS REPLACES THE OLD MOUTH ENTIRELY. The parametric face had no phoneme
// data anywhere near it, so the best available approach was to split the
// spectrum into low/mid/high and bend a mesh by it — an approximation of vowel
// shape with nothing to compare against. A VRM carries the real morphs, five of
// them (aa ih ou ee oh), authored by whoever built the model. The analysis
// hardly changes; where it POINTS changes completely.
//
// WHY BANDS AND NOT AMPLITUDE, STILL. Driving a mouth from loudness gives a
// puppet that flaps with the volume — wrong, because mouth SHAPE is set by
// formants, not level. The split into low/mid/high is what makes "oo" and "ee"
// come out different from nothing but an FFT, with no phoneme table and no
// per-language work, which matters when the language is Thai and viseme data is
// scarce.
//
// WHY TWO SIGNALS FROM TWO PLACES. How far the mouth OPENS comes from the raw
// waveform: an amplitude envelope read straight off the samples has no analysis
// lag at all, where the same envelope derived from FFT magnitudes inherits the
// window and the smoothing. WHICH SHAPE it makes stays on the FFT — vowel
// colour changes far slower than loudness, so it can afford latency the opening
// cannot. Getting this backwards is what makes a mouth look a beat behind.

const LOW = [0, 8], MID = [8, 40], HIGH = [40, 120];

/**
 * เล่นไปกี่วินาทีโดยไม่มีคลื่นเลยสักนิด ถึงนับว่า "เสียงไม่ออก"
 *
 * ยาวกว่าช่วงเงียบหัวไฟล์ของ TTS ทุกเจ้าที่เคยเจอ (สูงสุดราวครึ่งวินาที)
 * แต่สั้นพอที่สลับไปเล่นทางสำรองแล้วยังไม่รู้สึกว่าเธอเงียบไปนาน
 */
const SILENCE_PROBE = 1.2;

/**
 * Where each viseme sits on two axes: how open the mouth is, and how spread
 * (1) versus rounded (0) it is. Blending by distance on this plane means the
 * mouth moves BETWEEN shapes instead of snapping between five poses, which is
 * the difference between speech and a slideshow.
 */
const SHAPES = [
    { id: 'aa', open: 1.00, spread: 0.50 },
    { id: 'ih', open: 0.45, spread: 0.90 },
    { id: 'ee', open: 0.35, spread: 1.00 },
    { id: 'oh', open: 0.70, spread: 0.15 },
    { id: 'ou', open: 0.35, spread: 0.00 },
];

function band(data, [a, b]) {
    let s = 0;
    for (let i = a; i < b && i < data.length; i++) s += data[i];
    return s / Math.max(1, Math.min(b, data.length) - a) / 255;
}

export class LipSync {
    constructor() {
        this.speaking = false;
        this.level = 0;              // 0..1 loudness, for anything else that wants it

        // ── พูดพึมพำ (ไม่มีเสียงให้วิเคราะห์) ──────────────────
        //
        // ทางสำรองเท่านั้น · ปกติตอนอยู่ในสายปากอ่านคลื่นจากเสียงจริงที่เล่น
        // แบบปิดเสียง (ดู prepare) · ใช้โหมดนี้เฉพาะตอนไฟล์นั้นเล่นไม่ได้
        // และเปิดเฉพาะช่วงที่เธอพูด ไม่ใช่ทั้งสาย — ของเดิมเปิดทั้งสาย
        // ปากจึงขยับอยู่ตลอดแม้ตอนที่คู่สายพูดและเธอควรเงียบฟัง
        this.babble = false;
        this._bT = 0;
        this._bOn = false;
        this._bUntil = 0;
        this._bSpread = 0.3;
        this._bRate = 0;
        this._open = 0;
        this._spread = 0;
        this._tailUntil = 0;
        this._nodes = [];
        this._src = null;
        this._lag = null;
        this._ready = null;
        /** ปลายทางอัดคลิป — ดู setTap */
        this.tap = null;
        this.weights = { aa: 0, ih: 0, ou: 0, ee: 0, oh: 0 };
    }

    /**
     * AudioContext ตัวเดียวของเวที — สร้างตอนใช้ครั้งแรก ไม่ใช่ใน constructor
     *
     * Browsers refuse to start one outside a user gesture, and one created at
     * load time arrives suspended and silently stays that way — audible as "her
     * mouth never moves", with no error anywhere to explain it.
     */
    async context() {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        this.ctx = this.ctx || new Ctx();
        if (this.ctx.state === 'suspended') { try { await this.ctx.resume(); } catch {} }
        return this.ctx;
    }

    /**
     * ระยะจากที่ตัววิเคราะห์เห็นคลื่น ถึงที่ลำโพงออกเสียงจริง (วินาที)
     *
     * 🔴 ตัววิเคราะห์อ่านคลื่น**ก่อน**มันออกลำโพง · บนมือถือช่วงนั้นยาวพอ
     * ให้เห็นว่าปากขยับนำเสียง โดยเฉพาะลำโพง Bluetooth ที่หน่วงเป็นร้อยมิลลิวินาที
     * จึงหน่วงคลื่นฝั่งวิเคราะห์ไว้เท่าที่เบราว์เซอร์บอกว่าเสียงหน่วง
     * เครื่องที่ไม่บอก (ค่าเป็น 0/undefined) = ไม่หน่วง เหมือนของเดิม
     */
    outputLag() {
        const c = this.ctx;
        const lag = (Number(c?.outputLatency) || 0) + (Number(c?.baseLatency) || 0);
        return Math.min(0.3, Math.max(0, lag));
    }

    /**
     * Play an mp3 and drive the mouth from it. Resolves when it finishes.
     */
    async play(url) {
        this.stop();
        const audio = this._element(url);
        await this.context();
        // 🔴 context ที่ไม่ได้ running = เสียงเข้ากราฟแล้วหายเงียบ แต่ <audio>
        // ยังเดินจนจบและบอกว่า "เล่นสำเร็จ" · ให้ล้มตรงนี้ ฝั่งแอปจะได้สลับไป
        // เล่นทางเครื่องเล่นของ Android แทนที่จะปล่อยให้เธอเงียบโดยไม่มีใครรู้
        if (this.ctx.state !== 'running') throw new Error(`audio-context-${this.ctx.state}`);
        const lag = this.outputLag();
        this._wire(audio, { audible: true, delay: lag });
        const { ended } = await this._start(audio);
        const how = await Promise.race([
            ended.then(() => 'ended'),
            this._watchSilence(audio, lag),
        ]);
        if (how === 'silent') {
            this.stop();
            throw new Error('silent-output');
        }
        return true;
    }

    /**
     * จับเสียงที่ "เล่นอยู่แต่ไม่มีอะไรออกมา" — คืน 'silent' ถ้าเล่นไปแล้ว
     * [SILENCE_PROBE] วินาทีโดยไม่มีคลื่นเข้ากราฟเลย · เจอเสียงเมื่อไหร่ก็เลิกเฝ้า
     * (Promise นั้นค้างไว้เฉย ๆ ซึ่งไม่เป็นไร — การแข่งตัดสินที่ 'ended' แทน)
     *
     * ที่มา: เจ้าของเจอ "ไม่มีเสียงเฉยเลย" — ทางนี้คืนว่าเล่นสำเร็จทุกประโยค
     * แอปจึงไม่เคยลองทางสำรอง · สาเหตุที่ทำแบบนี้ได้มีหลายทางและเดาจากโค้ด
     * ไม่ได้ (WebView อัปเดตตัวเอง, context ถูกพักโดยระบบ, ตัวเล่นเสียงของ
     * WebView หลุด) · วัดคลื่นที่เข้ากราฟจริงจับได้ทุกทางในที่เดียว
     */
    _watchSilence(audio, lag) {
        const an = this.analyser;
        if (!an) return new Promise(() => {});
        const buf = new Uint8Array(an.fftSize);
        return new Promise(res => {
            const t = setInterval(() => {
                if (this.audio !== audio || audio.paused || audio.ended) {
                    clearInterval(t);
                    return;
                }
                an.getByteTimeDomainData(buf);
                for (let i = 0; i < buf.length; i++) {
                    if (Math.abs(buf[i] - 128) > 1) {
                        clearInterval(t);
                        return;
                    }
                }
                if (audio.currentTime >= SILENCE_PROBE + lag) {
                    clearInterval(t);
                    res('silent');
                }
            }, 80);
        });
    }

    /**
     * เตรียมขยับปากตามเสียงที่**ไม่ได้เล่นที่นี่** — เสียงเธอในสายโทรศัพท์
     *
     * 🔴 ตอนอยู่ในสาย เสียงจริงออกทางเนทีฟ (ช่องเสียงสาย) ห้ามดังจากเวทีซ้ำ
     * ของเดิมจึงให้ปาก "พึมพำ" แบบสุ่มไปตลอดทั้งสาย รวมทั้งตอนที่คู่สาย
     * กำลังพูดและเธอควรเงียบฟัง · ตอนนี้เล่นไฟล์เดียวกันที่นี่แบบ**ปิดเสียง**
     * (gain 0) แล้วอ่านคลื่นจากมันแทน ปากจึงขยับตามคำที่เธอพูดจริงในสาย
     *
     * แยกเป็นสองจังหวะ (prepare → go) เพราะการถอดไฟล์ใช้เวลาไม่แน่นอน
     * ถ้าเริ่มพร้อมกับฝั่งเนทีฟเลย ปากจะคลาดจากเสียงไปตามเวลาถอดไฟล์
     * เตรียมให้เสร็จก่อน แล้วค่อยปล่อยพร้อมเสียงจริง
     *
     * คืน true เมื่อพร้อม · false = เล่นไม่ได้ (ผู้เรียกตกไปพึมพำแทน)
     */
    async prepare(url) {
        this.stop();
        const audio = this._element(url);
        audio.preload = 'auto';
        await this.context();
        const ok = await new Promise(res => {
            const t = setTimeout(() => res(false), 3000);
            audio.oncanplaythrough = () => { clearTimeout(t); res(true); };
            audio.onerror = () => { clearTimeout(t); res(false); };
            audio.load();
        });
        if (!ok || this.audio !== audio) return false;
        this._wire(audio, { audible: false, delay: 0 });
        this._ready = audio;
        return true;
    }

    /**
     * ปล่อยปากที่เตรียมไว้ · lead = วินาทีที่หน่วงคลื่นให้ตรงกับเสียงที่ออก
     * ลำโพงจริง (ฝั่งเนทีฟต้องเตรียมเครื่องเล่นกับส่งเสียงออกลำโพงก่อน)
     */
    async go(lead = 0) {
        const audio = this._ready;
        this._ready = null;
        if (!audio || this.audio !== audio) return false;
        if (this._lag) this._lag.delayTime.value = Math.min(0.5, Math.max(0, lead));
        await this._start(audio);
        return true;
    }

    /**
     * ปลายทางอัดคลิป — เสียงเธอทุกประโยคไหลเข้าที่นี่ด้วย (ทั้งที่ดังจากเวที
     * และที่เล่นแบบปิดเสียงตอนอยู่ในสาย) · null = เลิกอัด
     */
    setTap(node) {
        if (this.tap && this._src) { try { this._src.disconnect(this.tap); } catch {} }
        this.tap = node || null;
        if (this.tap && this._src) { try { this._src.connect(this.tap); } catch {} }
    }

    _element(url) {
        const audio = new Audio(url);
        audio.crossOrigin = 'anonymous';
        this.audio = audio;
        return audio;
    }

    /**
     * ต่อ <audio> เข้ากราฟ
     *
     *   src ─┬─► ลำโพง                       (เฉพาะ audible)
     *        ├─► delay ─► analyser ─► gain 0 ─► ลำโพง   (ปาก · ต่อถึงปลายให้กราฟดึงข้อมูล)
     *        └─► tap                           (อัดคลิป)
     */
    _wire(audio, { audible, delay }) {
        for (const n of this._nodes) { try { n.disconnect(); } catch {} }
        const ctx = this.ctx;
        const src = ctx.createMediaElementSource(audio);
        const an = ctx.createAnalyser();
        // SMALL WINDOW, ALMOST NO SMOOTHING. smoothingTimeConstant is an
        // exponential average over frames: at 0.55 each frame is 55% history,
        // two or three frames of lag on top of the FFT window — enough to blur
        // consecutive syllables into one long vowel. Thai is syllable-timed, so
        // that blur is precisely what makes the mouth look out of step.
        an.fftSize = 256;
        an.smoothingTimeConstant = 0.1;
        const lag = ctx.createDelay(1);
        lag.delayTime.value = delay;
        const sink = ctx.createGain();
        sink.gain.value = 0;
        src.connect(lag);
        lag.connect(an);
        an.connect(sink);
        sink.connect(ctx.destination);
        if (audible) src.connect(ctx.destination);
        if (this.tap) src.connect(this.tap);

        this._src = src;
        this._lag = lag;
        this._nodes = [src, lag, an, sink];
        this.analyser = an;
        this.freq = new Uint8Array(an.frequencyBinCount);
        this.time = new Uint8Array(an.fftSize);
    }

    /**
     * เริ่มเล่น แล้วคืน `{ ended }` — **ห่อไว้ในออบเจกต์โดยตั้งใจ**
     * คืน Promise ตรง ๆ จาก async function จะถูกรวบเป็นการรอจนเล่นจบ
     * ซึ่งทำให้คนที่อยากรู้แค่ "เริ่มแล้ว" ต้องรอทั้งประโยค
     */
    async _start(audio) {
        this.speaking = true;
        this._tailUntil = 0;
        try { await audio.play(); } catch (e) {
            if (this.audio === audio) this.speaking = false;
            throw e;
        }
        // 🔴 จบด้วย pause ด้วย ไม่ใช่แค่ ended/error · stop() แค่ pause เสียง
        // ซึ่งไม่ยิง ended — ถ้าไม่ฟัง pause ฝั่ง Flutter ที่รอประโยคนี้อยู่
        // จะรอไปตลอดกาลทุกครั้งที่เธอถูกสั่งให้เงียบหรือมีประโยคใหม่มาแทรก
        const ended = new Promise(res => {
            audio.onended = res; audio.onerror = res; audio.onpause = res;
        }).then(() => {
            if (this.audio !== audio) return true;
            this.speaking = false;
            // จบเองตามธรรมชาติ = คลื่นช่วงท้ายยังค้างอยู่ในตัวหน่วง อ่านต่ออีก
            // เท่าที่หน่วงไว้ ไม่งั้นพยางค์สุดท้ายหายทุกประโยค
            // ถูกสั่งหยุด (pause) = ปิดปากทันที
            const d = this._lag?.delayTime.value ?? 0;
            this._tailUntil = audio.ended ? performance.now() + d * 1000 : 0;
            return true;
        });
        return { ended };
    }

    stop() {
        this._ready = null;
        this._tailUntil = 0;
        try { this.audio?.pause(); } catch {}
        this.speaking = false;
    }

    /**
     * Recompute the viseme weights. Call once a frame.
     * @param {number} dt seconds since the last call — the smoothing is a rate,
     *   not a per-frame constant, or the mouth steps whenever the frame rate does.
     */
    update(dt = 1 / 60) {
        const ease = (rate) => 1 - Math.exp(-rate * dt);
        let open = 0, spread = 0;

        const live = this.speaking
            || (this._tailUntil > 0 && performance.now() < this._tailUntil);
        if (live && this.analyser) {
            this.analyser.getByteTimeDomainData(this.time);
            let sum = 0;
            for (let i = 0; i < this.time.length; i++) {
                const v = (this.time[i] - 128) / 128;
                sum += v * v;
            }
            const rms = Math.sqrt(sum / this.time.length);
            // Gated by a noise floor, or room tone and codec hiss hold her
            // mouth permanently ajar between sentences.
            open = Math.min(1, Math.max(0, (rms - 0.012) * 6.2));
            this.level = Math.min(1, rms * 3.6);

            this.analyser.getByteFrequencyData(this.freq);
            const lo = band(this.freq, LOW), mid = band(this.freq, MID), hi = band(this.freq, HIGH);
            spread = Math.min(1, Math.max(0, hi * 2.4 + mid * 0.7 - lo * 0.6));
        } else if (this.babble) {
            const b = this._babbleShape(dt);
            open = b.open;
            spread = b.spread;
            this.level = open;
        } else {
            this.level += (0 - this.level) * ease(6.5);
        }

        // Asymmetric: mouths open faster than they close, and equal rates read
        // as mush. Attack near-instant, release merely quick — one that closes
        // as fast as it opens chatters between syllables.
        this._open += (open - this._open) * ease(open > this._open ? 138 : 29);
        this._spread += (spread - this._spread) * ease(25);

        return this.shape(this._open, this._spread);
    }

    /**
     * จังหวะปากตอนพูดพึมพำ — ไม่ได้มาจากเสียง แต่ต้องดูเหมือนคำพูด
     *
     * สองชั้น:
     * - **ชั้นประโยค** พูดเป็นช่วง 1.4–3.8 วิ แล้วเว้น 0.5–1.6 วิ
     *   คนไม่ได้พูดรัวไม่หยุด และการเว้นวรรคคือสิ่งที่ทำให้ดูเป็นบทสนทนา
     *   ไม่ใช่ปากที่ขยับตลอดเวลาแบบเครื่องจักร
     * - **ชั้นพยางค์** ผสมสามคลื่นที่ความถี่ไม่ลงตัวกัน จังหวะจะได้ไม่ซ้ำรอบ
     *   คลื่นเดียวจะเป็นจังหวะเป๊ะซึ่งตาจับได้ในไม่กี่วินาที
     *
     * แยกออกมาเป็นเมธอดบริสุทธิ์ (นอกจาก dt) เพื่อให้นับจังหวะได้ในเทสต์
     * โดยไม่ต้องมีเสียงและไม่ต้องมีเบราว์เซอร์
     */
    _babbleShape(dt) {
        this._bT += dt;

        if (this._bT > this._bUntil) {
            this._bOn = !this._bOn;
            this._bT = 0;
            this._bUntil = this._bOn
                ? 1.4 + Math.random() * 2.4
                : 0.5 + Math.random() * 1.1;
            // เปลี่ยนสีสระและความเร็วพูดทุกประโยค ไม่งั้นทุกประโยคเหมือนกันหมด
            this._bSpread = 0.15 + Math.random() * 0.5;
            this._bRate = 17 + Math.random() * 9;
        }

        if (!this._bOn) return { open: 0, spread: this._bSpread };

        const t = this._bT * this._bRate;
        const w = Math.sin(t) * 0.5
            + Math.sin(t * 0.61 + 1.7) * 0.3
            + Math.sin(t * 1.43 + 0.4) * 0.2;

        // มีพื้นเล็กน้อยระหว่างพยางค์ ไม่ปิดสนิททุกครั้ง
        //
        // วัดแล้ว: ปิดสนิทเกิน 60% ของเวลาอ่านว่า "เคี้ยว" ไม่ใช่ "พูด"
        // เพราะคนพูดจริงขากรรไกรอ้าค้างไว้ตลอดประโยค ปิดเฉพาะพยัญชนะ
        return {
            open: Math.max(0, Math.min(1, 0.14 + w * 0.72)),
            spread: this._bSpread,
        };
    }

    /**
     * Nearest-shapes blend on the (open, spread) plane, normalised so the
     * weights always sum to the current OPENING rather than to whatever the
     * distances happened to produce. Split out from `update` so the mapping can
     * be checked without an audio file, which is the only part of this worth
     * testing and the only part that has no browser dependency.
     */
    shape(open, spread) {
        let total = 0;
        const raw = SHAPES.map(s => {
            const d = Math.hypot((open - s.open) * 0.9, (spread - s.spread) * 1.1);
            const w = 1 / (0.08 + d * d * 6);
            total += w;
            return w;
        });
        for (let i = 0; i < SHAPES.length; i++)
            this.weights[SHAPES[i].id] = (raw[i] / total) * open;
        return this.weights;
    }

    /** Push the current weights onto a VRM's expression manager. */
    applyTo(vrm) {
        const em = vrm?.expressionManager;
        if (!em) return;
        for (const k in this.weights) em.setValue(k, this.weights[k]);
    }

    dispose() {
        this.stop();
        try { this.ctx?.close(); } catch {}
    }
}
