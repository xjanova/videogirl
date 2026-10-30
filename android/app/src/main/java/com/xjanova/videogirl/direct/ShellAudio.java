package com.xjanova.videogirl.direct;
import android.content.AttributionSource;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.pm.ApplicationInfo;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Looper;

import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;

/**
 * Experiment: can a process running as the adb shell user (uid 2000) put audio straight into
 * the call uplink (Telephony Tx) and read the caller straight from the downlink?
 *
 *   CLASSPATH=/data/local/tmp/teltx.dex app_process / TelTx list
 *   CLASSPATH=... app_process / TelTx play A|B|C [speech.wav]
 *   CLASSPATH=... app_process / TelTx rec <source> <seconds> <out.wav>
 */
final class ShellAudio {
    static final int RATE = 24000;
    static Context ctx;

    static void log(String s) {
        System.out.println(s);
        System.out.flush();
    }

    /** The scrcpy trick: an ActivityThread whose bound app is com.android.shell. */
    static void fillActivityThread() {
        try {
            Looper.prepareMainLooper();
        } catch (Throwable t) {
            log("looper: " + t);
        }
        try {
            Class<?> at = Class.forName("android.app.ActivityThread");
            Constructor<?> c = at.getDeclaredConstructor();
            c.setAccessible(true);
            Object thread = c.newInstance();
            Field cur = at.getDeclaredField("sCurrentActivityThread");
            cur.setAccessible(true);
            cur.set(null, thread);
            Field sys = at.getDeclaredField("mSystemThread");
            sys.setAccessible(true);
            sys.setBoolean(thread, true);
            Class<?> abd = Class.forName("android.app.ActivityThread$AppBindData");
            Constructor<?> ac = abd.getDeclaredConstructor();
            ac.setAccessible(true);
            Object data = ac.newInstance();
            ApplicationInfo ai = new ApplicationInfo();
            ai.packageName = "com.android.shell";
            Field aif = abd.getDeclaredField("appInfo");
            aif.setAccessible(true);
            aif.set(data, ai);
            Field mb = at.getDeclaredField("mBoundApplication");
            mb.setAccessible(true);
            mb.set(thread, data);
            Method gsc = at.getDeclaredMethod("getSystemContext");
            gsc.setAccessible(true);
            ctx = new ShellContext((Context) gsc.invoke(thread));
            // vivo's AudioRecord hook reads ActivityThread.currentApplication().getOpPackageName()
            android.app.Application app = new android.app.Application();
            Method attach = ContextWrapper.class.getDeclaredMethod("attachBaseContext", Context.class);
            attach.setAccessible(true);
            attach.invoke(app, ctx);
            Field ia = at.getDeclaredField("mInitialApplication");
            ia.setAccessible(true);
            ia.set(thread, app);
        } catch (Throwable t) {
            log("activity thread: " + t);
        }
    }

    static class ShellContext extends ContextWrapper {
        ShellContext(Context base) {
            super(base);
        }

        @Override
        public String getPackageName() {
            return "com.android.shell";
        }

        @Override
        public String getOpPackageName() {
            return "com.android.shell";
        }

        @Override
        public AttributionSource getAttributionSource() {
            return new AttributionSource.Builder(2000).setPackageName("com.android.shell").build();
        }

        @Override
        public int getDeviceId() {
            return 0;
        }

        @Override
        public Context getApplicationContext() {
            return this;
        }
    }

    static AudioDeviceInfo[] devices(int flags) throws Exception {
        Method m = AudioManager.class.getDeclaredMethod("getDevicesStatic", int.class);
        m.setAccessible(true);
        return (AudioDeviceInfo[]) m.invoke(null, flags);
    }

    static AudioDeviceInfo telephonyOut() throws Exception {
        for (AudioDeviceInfo d : devices(AudioManager.GET_DEVICES_OUTPUTS)) {
            if (d.getType() == AudioDeviceInfo.TYPE_TELEPHONY) return d;
        }
        return null;
    }

    static AudioManager audioManager() throws Exception {
        Constructor<AudioManager> c = AudioManager.class.getDeclaredConstructor(Context.class);
        c.setAccessible(true);
        return c.newInstance(ctx);
    }

    static void list() throws Exception {
        for (AudioDeviceInfo d : devices(AudioManager.GET_DEVICES_OUTPUTS)) {
            log("out id=" + d.getId() + " type=" + d.getType() + " " + d.getProductName());
        }
        for (AudioDeviceInfo d : devices(AudioManager.GET_DEVICES_INPUTS)) {
            log("in  id=" + d.getId() + " type=" + d.getType() + " " + d.getProductName());
        }
        AudioManager am = audioManager();
        log("mode=" + am.getMode());
        try {
            log("interceptable=" + AudioManager.class.getMethod("isPstnCallAudioInterceptable").invoke(am));
        } catch (Throwable t) {
            log("interceptable: " + t.toString());
        }
    }

    static AudioFormat format() {
        return new AudioFormat.Builder()
                .setSampleRate(RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build();
    }

    static AudioTrack build(AudioAttributes aa) {
        int min = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT);
        AudioTrack.Builder b = new AudioTrack.Builder()
                .setAudioAttributes(aa)
                .setAudioFormat(format())
                .setBufferSizeInBytes(Math.max(min * 4, RATE))
                .setTransferMode(AudioTrack.MODE_STREAM);
        // AudioTrack.Builder.setContext is API 34; on 33 it is a NoSuchMethodError, not an Exception.
        if (ctx != null && Build.VERSION.SDK_INT >= 34) b.setContext(ctx);
        return b.build();
    }

    static AudioTrack track(String variant) throws Exception {
        switch (variant) {
            case "A": {
                // ordinary voice track, steered to the Telephony Tx device
                AudioTrack t = build(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build());
                AudioDeviceInfo d = telephonyOut();
                log("telephony out device: " + (d == null ? "none" : d.getId()));
                if (d != null) log("setPreferredDevice: " + t.setPreferredDevice(d));
                return t;
            }
            case "B": {
                // system usage CALL_ASSISTANT (17): the policy routes it to the uplink during a call
                AudioAttributes.Builder ab = new AudioAttributes.Builder();
                Method m = AudioAttributes.Builder.class.getDeclaredMethod("setSystemUsage", int.class);
                m.setAccessible(true);
                m.invoke(ab, 17);
                return build(ab.setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build());
            }
            case "C": {
                // AudioManager.getCallUplinkInjectionAudioTrack (SystemApi, Android 13+)
                AudioManager am = audioManager();
                log("interceptable=" + AudioManager.class.getMethod("isPstnCallAudioInterceptable").invoke(am));
                Method g = AudioManager.class.getMethod("getCallUplinkInjectionAudioTrack", AudioFormat.class);
                return (AudioTrack) g.invoke(am, format());
            }
            default:
                throw new IllegalArgumentException(variant);
        }
    }


}
