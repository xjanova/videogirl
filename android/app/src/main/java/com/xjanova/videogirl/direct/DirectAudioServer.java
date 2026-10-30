package com.xjanova.videogirl.direct;

import android.media.*;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Process;
import android.os.SystemClock;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.atomic.AtomicLong;

/** Shell-only entry point. The launcher supplies the secret on stdin, never argv. */
public final class DirectAudioServer {
    private final int appUid;
    private final byte[] secret;
    private DirectAudioServer(int uid, String token) { appUid=uid; secret=token.getBytes(StandardCharsets.UTF_8); }

    public static void main(String[] args) throws Exception {
        if (Process.myUid()!=2000 || args.length!=2) throw new SecurityException("shell launcher required");
        int uid=Integer.parseInt(args[1]);
        if (uid<10000 || !args[0].matches("giggok_[a-zA-Z0-9_]{1,80}")) throw new SecurityException("bad identity");
        byte[] tokenBytes=new byte[64];
        new DataInputStream(System.in).readFully(tokenBytes);
        String token=new String(tokenBytes,StandardCharsets.US_ASCII);
        int terminator=System.in.read();
        if (terminator=='\r') terminator=System.in.read();
        if (terminator!='\n' || !token.matches("[a-fA-F0-9]{64}")) throw new SecurityException("bad token");
        ShellAudio.fillActivityThread();
        if (ShellAudio.ctx==null) throw new IllegalStateException("shell context unavailable");
        new DirectAudioServer(uid,token).serve(args[0]);
    }

    private void serve(String name) throws Exception {
        try (LocalServerSocket server=new LocalServerSocket(name)) {
            for (;;) {
                LocalSocket socket=server.accept();
                try {
                    if (socket.getPeerCredentials().getUid()!=appUid) { socket.close(); continue; }
                    socket.setSoTimeout(3000);
                    DataInputStream in=new DataInputStream(socket.getInputStream());
                    if (in.readInt()!=AudioProtocol.VERSION) { socket.close(); continue; }
                    byte[] offered=new byte[64]; in.readFully(offered);
                    if (!MessageDigest.isEqual(secret,offered)) { socket.close(); continue; }
                    socket.setSoTimeout(0);
                    try (Session session=new Session(socket)) { session.run(in); }
                } catch (Exception | LinkageError ignored) {
                    // One bad session must not take the helper down; the next call needs it.
                    socket.close();
                }
            }
        }
    }

    private static boolean supported() {
        try {
            return ShellAudio.telephonyOut()!=null && Boolean.TRUE.equals(AudioManager.class
                    .getMethod("isPstnCallAudioInterceptable").invoke(ShellAudio.audioManager()));
        } catch (Exception e) { return false; }
    }

    private static final class Session implements AutoCloseable {
        final LocalSocket socket;
        final DataOutputStream out;
        volatile boolean alive=true, injecting=false;
        AudioTrack track;
        volatile AudioRecord down, up;
        Thread reader, writer, ownerReader;
        final ArrayBlockingQueue<byte[]> queue=new ArrayBlockingQueue<>(100);
        final AtomicLong queued=new AtomicLong(), written=new AtomicLong();
        volatile long epochUs, lastCommandMs=SystemClock.elapsedRealtime();
        volatile long generation;
        final Thread watchdog;
        String variant="none";
        Session(LocalSocket socket) throws IOException {
            this.socket=socket; out=new DataOutputStream(socket.getOutputStream());
            // If the app stops draining events, closing the socket releases any blocked send.
            watchdog=new Thread(()-> {
                try {
                    while(alive) {
                        Thread.sleep(1000);
                        if(SystemClock.elapsedRealtime()-lastCommandMs>10000) { fail("client_timeout"); break; }
                    }
                } catch(InterruptedException ignored) { Thread.currentThread().interrupt(); }
            },"giggok-call-watchdog"); watchdog.setDaemon(true); watchdog.start();
        }
        void reply(int id,String value) throws IOException { AudioProtocol.write(out,AudioProtocol.REPLY,id,AudioProtocol.text(value)); }
        void run(DataInputStream in) throws Exception {
            while(alive) {
                AudioProtocol.Frame f=AudioProtocol.read(in);
                lastCommandMs=SystemClock.elapsedRealtime();
                try {
                    if(f.type!=AudioProtocol.WRITE && f.type!=AudioProtocol.TAKEOVER && f.data.length!=0)
                        throw new IOException("unexpected command payload");
                    switch(f.type) {
                        case AudioProtocol.STATUS: reply(f.id,supported()?"ready":"unsupported"); break;
                        case AudioProtocol.START: reply(f.id,start()?"direct:"+variant:"unavailable"); break;
                        case AudioProtocol.WRITE:
                            if (!injecting || f.data.length==0 || (f.data.length&1)!=0 || f.data.length>9600)
                                throw new IOException("invalid audio write");
                            // Bound latency and memory even if a producer runs faster than playback.
                            if (queued.get()+f.data.length>96000) throw new IOException("audio backpressure");
                            queued.addAndGet(f.data.length);
                            if(!queue.offer(f.data)) { queued.addAndGet(-f.data.length); throw new IOException("audio queue full"); }
                            reply(f.id,"ok"); break;
                        case AudioProtocol.CLEAR:
                            long cutUs=nowUs(), pendingMs=pending();
                            clear(); reply(f.id,"ok:"+cutUs+":"+pendingMs); break;
                        case AudioProtocol.PENDING: reply(f.id,Long.toString(pending())); break;
                        case AudioProtocol.TAKEOVER:
                            if(f.data.length>1 || (f.data.length==1 && f.data[0]!=0 && f.data[0]!=1))
                                throw new IOException("invalid recording choice");
                            long takeoverUs=nowUs();
                            stopPlayback();
                            if(f.data.length==1 && f.data[0]==1) {
                                boolean owner=startOwnerCapture();
                                reply(f.id,(owner?"recording_owner:":"owner_capture_unavailable:")+takeoverUs);
                            } else {
                                stopCapture(); reply(f.id,"stopped:"+takeoverUs);
                            }
                            break;
                        case AudioProtocol.STOP: stop(); reply(f.id,"ok"); break;
                        default: throw new IOException("unknown command");
                    }
                } catch (Exception e) {
                    stop();
                    reply(f.id,"error:"+e.getClass().getSimpleName());
                }
            }
        }
        boolean start() {
            stop();
            if(!supported()) return false;
            try {
                if(ShellAudio.audioManager().getMode()!=AudioManager.MODE_IN_CALL) return false;
                down=capture(MediaRecorder.AudioSource.VOICE_DOWNLINK);
                for(String candidate:new String[]{"C","A","B"}) {
                    AudioTrack trial=null;
                    try {
                        trial=ShellAudio.track(candidate);
                        trial.play();
                        // Silence establishes a route; never emit a test tone into a real call.
                        trial.write(new byte[960],0,960);
                        AudioDeviceInfo route=trial.getRoutedDevice();
                        if(route==null || route.getType()!=AudioDeviceInfo.TYPE_TELEPHONY) throw new IOException("wrong route");
                        track=trial; variant=candidate; break;
                    } catch(Exception | LinkageError ignored) {
                        // A hidden API missing on this ROM is a failed variant; try the next one.
                        if(trial!=null) trial.release();
                    }
                }
                if(track==null) throw new IOException("no uplink route");
                epochUs=SystemClock.elapsedRealtimeNanos()/1000;
                // The route-probe wrote 480 frames, including any still buffered.
                written.set(480);
                injecting=true;
                reader=captureThread(down,AudioProtocol.DOWNLINK);
                startWriter();
                return true;
            } catch(Exception e) { stop(); return false; }
        }
        AudioRecord capture(int source) throws Exception {
            int min=AudioRecord.getMinBufferSize(16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT);
            AudioRecord r=new AudioRecord.Builder().setContext(ShellAudio.ctx).setAudioSource(source)
                .setAudioFormat(new AudioFormat.Builder().setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(Math.max(min*4,6400)).build();
            try { r.startRecording(); if(r.getRecordingState()!=AudioRecord.RECORDSTATE_RECORDING) throw new IOException("capture not started"); return r; }
            catch(Exception e) { r.release(); throw e; }
        }
        Thread captureThread(AudioRecord record,int type) {
            final long captureEpoch=epochUs;
            Thread t=new Thread(()-> {
                byte[] pcm=new byte[640];
                long nextUs=-1;
                try {
                    while(alive && (record==down || record==up)) {
                        int n=record.read(pcm,0,pcm.length);
                        if(n<=0) throw new IOException("capture stopped");
                        if(!alive || (record!=down && record!=up)) break;
                        long durationUs=n*1000000L/32000;
                        if(nextUs<0) nextUs=Math.max(0,SystemClock.elapsedRealtimeNanos()/1000-captureEpoch-durationUs);
                        AudioProtocol.write(out,type,0,AudioProtocol.audio(nextUs,pcm,n));
                        nextUs+=durationUs;
                    }
                } catch(Exception e) { if(alive && (record==down || record==up)) fail("capture_lost"); }
            },"giggok-call-capture"); t.setDaemon(true); t.start(); return t;
        }
        void startWriter() {
            final long ownGeneration=generation;
            writer=new Thread(()->writeLoop(ownGeneration),"giggok-uplink"); writer.setDaemon(true); writer.start();
        }
        void writeLoop(long ownGeneration) {
            try {
                while(injecting && ownGeneration==generation) {
                    byte[] pcm=queue.take();
                    int off=0;
                    while(off<pcm.length && injecting && ownGeneration==generation) {
                        int n;
                        long at;
                        synchronized(this) {
                            if(track==null || !injecting || ownGeneration!=generation) break;
                            // start()/clear() proved the route; null is a transient re-route, not a speaker.
                            AudioDeviceInfo route=track.getRoutedDevice();
                            if(route!=null && route.getType()!=AudioDeviceInfo.TYPE_TELEPHONY) throw new IOException("uplink route lost");
                            long pendingFrames=Math.max(0,written.get()-(track.getPlaybackHeadPosition()&0xffffffffL));
                            at=SystemClock.elapsedRealtimeNanos()/1000-epochUs+pendingFrames*1000000L/24000;
                            n=track.write(pcm,off,pcm.length-off,AudioTrack.WRITE_NON_BLOCKING);
                            if(n>0) { written.addAndGet(n/2); queued.addAndGet(-n); }
                        }
                        if(n<0) throw new IOException("playback stopped");
                        if(n==0) { Thread.sleep(5); continue; }
                        byte[] sent=java.util.Arrays.copyOfRange(pcm,off,off+n);
                        AudioProtocol.write(out,AudioProtocol.PLAYED,0,AudioProtocol.audio(at,sent,n));
                        off+=n;
                    }
                }
            } catch(InterruptedException ignored) { Thread.currentThread().interrupt(); }
            catch(Exception e) { if(injecting && ownGeneration==generation) fail("uplink_lost"); }
        }
        synchronized long pending() {
            if(track==null) return 0;
            return (Math.max(0,written.get()-(track.getPlaybackHeadPosition()&0xffffffffL))+queued.get()/2)*1000/24000;
        }
        long nowUs() { return Math.max(0,SystemClock.elapsedRealtimeNanos()/1000-epochUs); }
        void clear() throws Exception {
            if(down==null || !injecting) throw new IOException("no active injection");
            // Stop the old writer before replacing its track/queue; no stale PCM survives barge-in.
            stopPlayback();
            AudioTrack fresh=ShellAudio.track(variant);
            try {
                fresh.play();
                // Same silent route probe as start(): a fresh track has no route until its first write.
                fresh.write(new byte[960],0,960);
                AudioDeviceInfo route=fresh.getRoutedDevice();
                if(route==null || route.getType()!=AudioDeviceInfo.TYPE_TELEPHONY) throw new IOException("wrong route");
            } catch(Exception e) { fresh.release(); throw e; }
            synchronized(this) { track=fresh; written.set(480); }
            injecting=true;
            startWriter();
        }
        void stopPlayback() {
            injecting=false;
            generation++;
            Thread old=writer; writer=null;
            if(old!=null) old.interrupt();
            synchronized(this) {
                if(track!=null) { try { track.pause(); track.flush(); } catch(Exception ignored) {} track.release(); track=null; }
            }
            join(old);
            queue.clear(); queued.set(0); written.set(0);
        }
        boolean startOwnerCapture() {
            if(down==null) return false;
            if(up!=null) return true;
            try { up=capture(MediaRecorder.AudioSource.VOICE_UPLINK); ownerReader=captureThread(up,AudioProtocol.UPLINK); return true; }
            catch(Exception e) { return false; }
        }
        void stop() {
            stopPlayback();
            stopCapture();
        }
        void stopCapture() {
            AudioRecord d=down,u=up; down=null; up=null;
            release(d); release(u);
            join(reader); join(ownerReader); reader=null; ownerReader=null;
        }
        void join(Thread t) {
            if(t==null || t==Thread.currentThread()) return;
            try { t.join(1000); } catch(InterruptedException e) { Thread.currentThread().interrupt(); }
            if(t.isAlive()) { fail("worker_stalled"); throw new IllegalStateException("worker_stalled"); }
        }
        void release(AudioRecord r) { if(r!=null) { try { r.stop(); } catch(Exception ignored) {} r.release(); } }
        void fail(String reason) {
            injecting=false; alive=false;
            // Do not attempt another write: the failure itself may be a blocked output stream.
            try { socket.close(); } catch(IOException ignored) {}
        }
        public void close() {
            alive=false; watchdog.interrupt();
            try { socket.close(); } catch(IOException ignored) {}
            try { stop(); } catch(Exception ignored) { stopCapture(); }
        }
    }
}
