// recorder.js — อัดเวทีของเธอเป็นคลิปวิดีโอ พร้อมเสียงเธอ (และไมค์ถ้าขอ)
//
// WHY RECORD HERE AND NOT THE SCREEN. Android's screen recorder needs a
// system consent dialog every single time, records the status bar and every
// button on top of her, and can't be told to leave the app's UI out. The canvas
// already holds exactly the picture we want — her, on the chosen backdrop, at
// the canvas's own resolution — so the clip is read straight off it.
//
// WHY THE AUDIO IS MIXED HERE. Her voice never touches Android's audio path in
// a way an app can record (and during a phone call it goes out on the call
// stream, which is off-limits entirely). Every sentence she says is played
// through LipSync's graph, so a tap on that graph carries her voice into the
// clip at full quality, with no microphone and no room echo. The microphone is
// optional and goes into the mix only — never to the speaker, or it would feed
// back.
//
// WHY CHUNKS ARE CHAINED. MediaRecorder hands out a Blob every second and the
// Blob → base64 read is async. Two reads in flight can finish out of order, and
// a container written out of order is a file that will not play. Each chunk
// waits for the previous one to be posted before it starts reading.

const TYPES = [
    'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
    'video/mp4;codecs=avc1,opus',
    'video/mp4',
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
];

/** ชนิดไฟล์แรกที่เครื่องนี้อัดได้ · '' = ให้เบราว์เซอร์เลือกเอง */
export function pickType() {
    if (typeof MediaRecorder !== 'function') return '';
    for (const t of TYPES) {
        try { if (MediaRecorder.isTypeSupported(t)) return t; } catch {}
    }
    return '';
}

function toBase64(blob) {
    return new Promise((res, rej) => {
        const r = new FileReader();
        r.onload = () => {
            const s = String(r.result ?? '');
            res(s.slice(s.indexOf(',') + 1));
        };
        r.onerror = () => rej(r.error);
        r.readAsDataURL(blob);
    });
}

export class StageRecorder {
    /**
     * @param {HTMLCanvasElement} canvas ผืนผ้าใบของ renderer
     * @param {import('./lipsync.js').LipSync} lip ท่อเสียงของเธอ
     * @param {(type:string, data:object)=>void} post ส่งข้อความกลับฝั่ง Flutter
     */
    constructor(canvas, lip, post) {
        this.canvas = canvas;
        this.lip = lip;
        this.post = post;
        this.rec = null;
    }

    get active() { return !!this.rec; }

    /**
     * เริ่มอัด · คืน { ok, mime, mic, why? }
     *
     * ไมค์ขอไม่ได้ไม่ใช่เหตุให้ไม่อัด — อัดต่อด้วยเสียงเธออย่างเดียว แล้วบอก
     * กลับไปว่าไมค์ไม่ติด (`mic: false`) ให้ฝั่งแอปแจ้งผู้ใช้เอง
     */
    async start({ mic = false, fps = 30, kbps = 4000 } = {}) {
        if (this.rec) return { ok: true, mime: this.rec.mimeType, mic: !!this.micStream };
        if (typeof MediaRecorder !== 'function' || typeof this.canvas?.captureStream !== 'function') {
            return { ok: false, why: 'no-recorder' };
        }

        const ctx = await this.lip.context();
        const mix = ctx.createMediaStreamDestination();
        this.mix = mix;
        this.lip.setTap(mix);

        let micOn = false;
        if (mic) {
            try {
                this.micStream = await navigator.mediaDevices.getUserMedia({
                    audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
                });
                this.micNode = ctx.createMediaStreamSource(this.micStream);
                this.micNode.connect(mix);
                micOn = true;
            } catch (e) {
                this.micError = String(e?.name ?? e);
            }
        }

        try {
            this.video = this.canvas.captureStream(fps);
            const stream = new MediaStream([
                ...this.video.getVideoTracks(),
                ...mix.stream.getAudioTracks(),
            ]);
            const type = pickType();
            const opts = { videoBitsPerSecond: kbps * 1000, audioBitsPerSecond: 128000 };
            if (type) opts.mimeType = type;
            const rec = new MediaRecorder(stream, opts);
            this.rec = rec;
            this.seq = 0;
            this.chain = Promise.resolve();

            rec.ondataavailable = (e) => {
                if (!e.data || !e.data.size) return;
                const seq = this.seq++;
                const blob = e.data;
                this.chain = this.chain
                    .then(() => toBase64(blob))
                    .then((b64) => this.post('rec-chunk', { seq, b64 }))
                    .catch((err) => this.post('rec-failed', { why: String(err?.message ?? err) }));
            };
            rec.onerror = (e) => {
                this.post('rec-failed', { why: String(e?.error?.name ?? e?.error ?? 'recorder error') });
            };
            rec.onstop = () => {
                // ก้อนสุดท้ายมาก่อน stop เสมอ · รอให้มันส่งครบก่อนบอกว่าจบ
                const mime = rec.mimeType || type || 'video/webm';
                const chunks = this.seq;
                this.chain.then(() => this.post('rec-done', { mime, chunks }));
                this._release();
            };
            // ก้อนละวินาที · ก้อนใหญ่กว่านี้ทำให้สะพานข้ามไป Flutter สะดุดเป็นช่วง ๆ
            // ก้อนเล็กกว่านี้ทำให้ข้อความรัวจนเปลือง
            rec.start(1000);
            return { ok: true, mime: rec.mimeType || type, mic: micOn };
        } catch (e) {
            this._release();
            return { ok: false, why: String(e?.message ?? e) };
        }
    }

    /** หยุดอัด · ผลลัพธ์มาทาง 'rec-done' หลังก้อนสุดท้ายถูกส่งครบ */
    stop() {
        const rec = this.rec;
        if (!rec) return false;
        try {
            if (rec.state !== 'inactive') rec.stop();
            else this._release();
        } catch {
            this._release();
        }
        return true;
    }

    /**
     * ปล่อยทุกอย่างที่จับไว้ · ไมค์ที่ลืมปิดคือจุดเขียวมุมจอที่ค้างอยู่หลังเลิก
     * อัด ซึ่งในสายตาผู้ใช้คือแอปแอบฟัง
     */
    _release() {
        this.rec = null;
        this.lip.setTap(null);
        try { this.micNode?.disconnect(); } catch {}
        for (const t of this.micStream?.getTracks() ?? []) { try { t.stop(); } catch {} }
        for (const t of this.video?.getTracks() ?? []) { try { t.stop(); } catch {} }
        this.micNode = null;
        this.micStream = null;
        this.video = null;
        this.mix = null;
    }

    dispose() {
        this.stop();
        this._release();
    }
}
