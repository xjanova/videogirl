// startle.js — ท่าตกใจ: สะดุ้ง ไหล่ยก มือสองข้างชักขึ้นมาหน้าอก ตัวถอยหลังนิดหนึ่ง แล้วค่อยคลาย
//
// WHY THIS IS NOT A CLIP. A clip takes the body away from whatever she was
// doing, and being startled happens ON TOP of what you were doing — mid-sentence,
// sitting down, holding the phone. So this is a delta multiplied onto each bone
// after the clip and the procedural layer have both written it. She flinches
// from the pose she is actually in.
//
// It also means she can do it with no .fbx on the device at all, which a clip
// cannot. Motion files are not in git (see clips.json); this is code.
//
// WHY THE ATTACK IS THIS FAST. Every other motion here eases in over a third of
// a second, because a gesture is something she decides to do. A flinch is not
// decided. Ninety milliseconds is what separates "startled" from "shrugging";
// the release is slow for the same reason — the fright takes a moment to leave.

import * as THREE from 'three';

/**
 * [seconds, how much of the pose]. Up in 90ms, a beat of being frozen there,
 * then the long breath out.
 */
const KEYS = [[0, 0], [0.09, 1], [0.26, 0.92], [0.62, 0.58], [1.05, 0.18], [1.5, 0]];

export const STARTLE_SECONDS = KEYS[KEYS.length - 1][0];

/** How far into the pose she is at `t` seconds. Zero outside the flinch. */
export function startleAmount(t) {
    if (t <= 0 || t >= STARTLE_SECONDS) return 0;
    for (let i = 1; i < KEYS.length; i++) {
        const [t1, a1] = KEYS[i];
        if (t > t1) continue;
        const [t0, a0] = KEYS[i - 1];
        const x = (t - t0) / (t1 - t0);
        return a0 + (a1 - a0) * x * x * (3 - 2 * x);
    }
    return 0;
}

/**
 * The flinch at full strength, as Euler offsets in each bone's own frame.
 * x tips forward, so negative leans back. For the left side z lifts and
 * negative y brings the arm forward; the right side is the mirror.
 *
 * The neck and head tuck forward against the lean so she keeps looking at the
 * person in front of her. Leaning back as one rigid piece reads as falling over.
 */
const PEAK = {
    spine:         [-0.09, 0, 0],
    chest:         [-0.10, 0, 0],
    upperChest:    [-0.06, 0, 0],
    neck:          [0.09, 0, 0],
    head:          [0.05, 0, 0],
    leftShoulder:  [0, 0, 0.24],
    rightShoulder: [0, 0, -0.24],
    leftUpperArm:  [0, -0.62, 0.16],
    rightUpperArm: [0, 0.62, -0.16],
    leftLowerArm:  [0, -1.28, 0],
    rightLowerArm: [0, 1.28, 0],
    leftHand:      [0, 0, 0.20],
    rightHand:     [0, 0, -0.20],
};

/**
 * The bones that fling the hands up. PEAK assumes they start hanging at her
 * sides. Sitting or holding the phone they are already in front of her, and the
 * same rotation crosses them over her face, so the caller turns these down.
 */
const ARMS = new Set([
    'leftUpperArm', 'rightUpperArm', 'leftLowerArm', 'rightLowerArm', 'leftHand', 'rightHand',
]);

export class Startle {
    constructor(vrm) {
        this.bones = [];
        this.level = 0;           // read by the face
        this._t = -1;
        const e = new THREE.Euler();
        const flip = vrm.meta?.metaVersion === '0';
        for (const [name, [x, y, z]] of Object.entries(PEAK)) {
            const node = vrm.humanoid?.getNormalizedBoneNode(name);
            if (!node) continue;  // optional bones (upperChest) may be absent
            const peak = new THREE.Quaternion().setFromEuler(e.set(x, y, z, 'XYZ'));
            if (flip) { peak.x = -peak.x; peak.z = -peak.z; }
            this.bones.push({ node, peak, now: new THREE.Quaternion(), arm: ARMS.has(name) });
        }
    }

    get active() { return this._t >= 0; }

    /** A second fright inside the first is the same fright, not a stutter. */
    fire() {
        if (this.active) return false;
        this._t = 0;
        return true;
    }

    /**
     * After every other body layer: it multiplies onto what they wrote.
     *
     * @param {number} dt seconds since the last frame
     * @param {number} armWeight 1 when her arms hang free, less when a clip has them
     */
    apply(dt, armWeight = 1) {
        if (!this.active) return;
        this._t += dt;
        if (this._t >= STARTLE_SECONDS) {
            this._t = -1;
            this.level = 0;
            return;
        }
        this.level = startleAmount(this._t);
        for (const b of this.bones) {
            b.now.identity().slerp(b.peak, b.arm ? this.level * armWeight : this.level);
            b.node.quaternion.multiply(b.now);
        }
    }
}
