package com.xjanova.videogirl

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.xjanova.videogirl.direct.AudioProtocol as P
import com.xjanova.videogirl.direct.setup.DirectAudioSetup
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** One authenticated helper connection per app process, shared by screen/headless engines. */
object DirectAudioClient {
    private var socket: Socket? = null
    private var output: DataOutputStream? = null
    private val ids = AtomicInteger()
    private val waiting = ConcurrentHashMap<Int, CompletableFuture<String>>()
    private val main = Handler(Looper.getMainLooper())
    private val work = Executors.newSingleThreadExecutor()
    @Volatile private var lastRequestMs = 0L
    @Volatile var active = false
        private set

    // The helper drops a session after 10 s without a command. During a call Dart can go quiet
    // for longer (realtime connect, the owner talking after take-over while both sides record).
    private val keepAlive: Runnable = object : Runnable {
        override fun run() {
            if (!active) return
            if (SystemClock.elapsedRealtime() - lastRequestMs > 3000) {
                work.execute { try { if (active) request(P.PENDING) } catch (_: Exception) { lost() } }
            }
            main.postDelayed(this, 2000)
        }
    }
    @Volatile private var acceptingAudio = false
    @Volatile private var recordOwner = false
    @Volatile private var sink: EventChannel.EventSink? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        EventChannel(messenger, "giggok/direct_audio_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        MethodChannel(messenger, "giggok/direct_audio").setMethodCallHandler { call, result ->
            // Disable producer immediately; queued writes cannot overtake take-over/stop.
            if (call.method == "takeover" || call.method == "stop" || call.method == "clear") acceptingAudio = false
            work.execute {
                try {
                    val answer: Any? = when (call.method) {
                        "start" -> {
                            recordOwner = call.argument<Boolean>("record") == true
                            connect(context)
                            val value = request(P.START)
                            active = value.startsWith("direct:")
                            acceptingAudio = active
                            if (active) {
                                main.post {
                                    CallAudio.ownerRouted = true
                                    MindInCallService.setSpeaker(false)
                                    main.removeCallbacks(keepAlive)
                                    main.postDelayed(keepAlive, 2000)
                                }
                            }
                            value
                        }
                        "status" -> { connect(context); request(P.STATUS) }
                        "write" -> {
                            val pcm = call.argument<ByteArray>("pcm") ?: byteArrayOf()
                            if (acceptingAudio && pcm.isNotEmpty()) {
                                // Frame limits are independent of the server's response chunk sizes.
                                var off = 0
                                while (off < pcm.size && acceptingAudio) {
                                    val end = minOf(off + 9600, pcm.size)
                                    check(request(P.WRITE, pcm.copyOfRange(off, end)) == "ok")
                                    off = end
                                }
                            }
                            true
                        }
                        "pending" -> if (active) request(P.PENDING).toIntOrNull() ?: 0 else 0
                        "clear" -> { val value = request(P.CLEAR); acceptingAudio = active && value.startsWith("ok:"); value }
                        "takeover" -> request(P.TAKEOVER, byteArrayOf(if (recordOwner) 1 else 0))
                        "stop" -> {
                            val value = if (active) request(P.STOP) else "ok"
                            // The helper serves one session at a time; free it for setup probes and the next call.
                            disconnect()
                            value
                        }
                        else -> null
                    }
                    main.post { if (answer == null) result.notImplemented() else result.success(answer) }
                } catch (e: Exception) {
                    disconnect()
                    val reason = e.message.takeIf { it == "not_configured" } ?: e.javaClass.simpleName
                    main.post { result.error("direct_unavailable", reason, null) }
                }
            }
        }
    }

    @Synchronized private fun connect(context: Context) {
        if (socket != null) return
        val channel = DirectAudioSetup.open(context)
        try {
            // Events arrive whenever the call produces them; only the handshake had a deadline.
            channel.socket.soTimeout = 0
            output = channel.output; socket = channel.socket
            Thread({ read(channel.socket, channel.input) }, "giggok-direct-events").apply { isDaemon = true; start() }
        } catch(e: Exception) { channel.close(); throw e }
    }
    private fun lost() {
        val wasActive = active
        disconnect()
        if (wasActive) main.post { sink?.error("direct_lost", "Call audio helper disconnected", null) }
    }
    private fun read(local: Socket, input: DataInputStream) {
        try {
            while (true) {
                val f = P.read(input)
                if (f.type == P.REPLY) {
                    waiting.remove(f.id)?.complete(f.text())
                } else if (f.type == P.ERROR) {
                    throw IllegalStateException(f.text())
                } else if (f.type in P.DOWNLINK..P.UPLINK && f.data.size >= 8) {
                    val at = ByteBuffer.wrap(f.data, 0, 8).long
                    val source = when(f.type) { P.DOWNLINK -> "down"; P.PLAYED -> "her"; else -> "owner" }
                    val event = mapOf("source" to source, "timeUs" to at,
                        "rate" to if (f.type == P.PLAYED) 24000 else 16000,
                        "pcm" to f.data.copyOfRange(8, f.data.size))
                    main.post { sink?.success(event) }
                }
            }
        } catch(e: Exception) {
            if (socket === local) {
                disconnect()
                main.post { sink?.error("direct_lost", "Call audio helper disconnected", null) }
            }
        }
    }
    private fun request(type: Int, bytes: ByteArray = byteArrayOf()): String {
        val id = ids.incrementAndGet()
        lastRequestMs = SystemClock.elapsedRealtime()
        val future = CompletableFuture<String>()
        waiting[id] = future
        try {
            val out = output ?: error("not connected")
            P.write(out, type, id, bytes)
            return future.get(3, TimeUnit.SECONDS)
        } finally { waiting.remove(id) }
    }
    @Synchronized private fun disconnect() {
        active = false; acceptingAudio = false
        val old = socket; socket = null; output = null
        try { old?.close() } catch (_: Exception) {}
        waiting.values.forEach { it.completeExceptionally(IllegalStateException("disconnected")) }
        waiting.clear()
    }
    /** Native call-screen take-over must cut injection before Dart catches up. */
    fun handOver() {
        acceptingAudio = false
        if (!active) return
        work.execute { try { request(P.TAKEOVER, byteArrayOf(if (recordOwner) 1 else 0)) } catch (_: Exception) { disconnect() } }
    }
    fun closeCall() {
        acceptingAudio = false
        if (!active) return
        work.execute { try { request(P.STOP) } catch (_: Exception) {} finally { disconnect() } }
    }
}
