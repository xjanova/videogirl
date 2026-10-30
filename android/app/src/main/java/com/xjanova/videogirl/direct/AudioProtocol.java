package com.xjanova.videogirl.direct;

import java.io.*;
import java.nio.charset.StandardCharsets;

/** Versioned, bounded framing. No command accepts a path or shell expression. */
public final class AudioProtocol {
    private AudioProtocol() {}
    public static final int VERSION = 1, MAX_PAYLOAD = 32768;
    public static final int STATUS = 1, START = 2, WRITE = 3, CLEAR = 4,
            PENDING = 5, TAKEOVER = 6, STOP = 7;
    public static final int REPLY = 100, DOWNLINK = 101, PLAYED = 102, UPLINK = 103, ERROR = 104;
    public static final class Frame {
        public final int type, id;
        public final byte[] data;
        public Frame(int type, int id, byte[] data) { this.type=type; this.id=id; this.data=data; }
        public String text() { return new String(data, StandardCharsets.UTF_8); }
    }
    public static Frame read(DataInputStream in) throws IOException {
        int type=in.readInt(), id=in.readInt(), length=in.readInt();
        if (length < 0 || length > MAX_PAYLOAD) throw new IOException("invalid frame length");
        byte[] data=new byte[length]; in.readFully(data);
        return new Frame(type,id,data);
    }
    public static void write(DataOutputStream out,int type,int id,byte[] data) throws IOException {
        if (data.length > MAX_PAYLOAD) throw new IOException("frame too large");
        synchronized(out) { out.writeInt(type); out.writeInt(id); out.writeInt(data.length); out.write(data); out.flush(); }
    }
    public static byte[] text(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    public static byte[] audio(long timeUs,byte[] pcm,int count) throws IOException {
        if(timeUs<0 || count<0 || count>pcm.length || (count&1)!=0 || count>MAX_PAYLOAD-8)
            throw new IOException("invalid audio packet");
        ByteArrayOutputStream bytes=new ByteArrayOutputStream(count+8);
        DataOutputStream out=new DataOutputStream(bytes); out.writeLong(timeUs); out.write(pcm,0,count);
        return bytes.toByteArray();
    }
}
