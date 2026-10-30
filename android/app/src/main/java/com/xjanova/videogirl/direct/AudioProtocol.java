package com.xjanova.videogirl.direct;

import java.io.*;
import java.nio.charset.StandardCharsets;

/** Versioned, bounded framing. No command accepts a path or shell expression. */
public final class AudioProtocol {
    private AudioProtocol() {}
    public static final int VERSION = 2, MAX_PAYLOAD = 32768;
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
    /** SELinux keeps apps out of the shell user's unix sockets, so the helper listens on loopback TCP,
     *  where any app could connect or take the port first. Both ends therefore prove they hold the pairing
     *  token without ever sending it, over fresh nonces from both sides so a recorded exchange cannot be replayed. */
    public static final int NONCE = 32;
    public static final class HandshakeException extends IOException { public HandshakeException(String m) { super(m); } }
    private static byte[] mac(byte[] key,String label,byte[] first,byte[] second) throws IOException {
        try {
            javax.crypto.Mac m=javax.crypto.Mac.getInstance("HmacSHA256");
            m.init(new javax.crypto.spec.SecretKeySpec(key,"HmacSHA256"));
            m.update(label.getBytes(StandardCharsets.US_ASCII)); m.update(first); m.update(second);
            return m.doFinal();
        } catch (java.security.GeneralSecurityException e) { throw new IOException("hmac unavailable"); }
    }
    private static byte[] nonce() { byte[] n=new byte[NONCE]; new java.security.SecureRandom().nextBytes(n); return n; }
    /** App side: returns only when whoever owns the port proved it holds the token. */
    public static void clientHello(DataInputStream in,DataOutputStream out,byte[] key) throws IOException {
        byte[] mine=nonce();
        out.writeInt(VERSION); out.write(mine); out.flush();
        byte[] theirs=new byte[NONCE]; in.readFully(theirs);
        byte[] proof=new byte[32]; in.readFully(proof);
        if (!java.security.MessageDigest.isEqual(proof,mac(key,"giggok-helper",mine,theirs))) throw new HandshakeException("helper_not_proven");
        out.write(mac(key,"giggok-app",theirs,mine)); out.flush();
    }
    /** Helper side: returns only when the caller proved it holds the token. */
    public static void serverHello(DataInputStream in,DataOutputStream out,byte[] key) throws IOException {
        int version=in.readInt();
        if (version!=VERSION) throw new HandshakeException("bad version "+version);
        byte[] theirs=new byte[NONCE]; in.readFully(theirs);
        byte[] mine=nonce();
        out.write(mine); out.write(mac(key,"giggok-helper",theirs,mine)); out.flush();
        byte[] proof=new byte[32]; in.readFully(proof);
        if (!java.security.MessageDigest.isEqual(proof,mac(key,"giggok-app",mine,theirs))) throw new HandshakeException("app_not_proven");
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
