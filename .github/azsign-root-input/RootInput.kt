package com.carriez.flutter_hbb

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import hbb.KeyEventConverter
import hbb.MessageOuterClass
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** MCD-125 pilot, explicitly enabled by a private marker provisioned over ADB. */
object RootInput {
    @Volatile var isReady = false
        private set
    @Volatile private var running = false
    @Volatile private var child: java.lang.Process? = null
    private val commands = ArrayBlockingQueue<String>(128)
    private var mouseX = 0
    private var mouseY = 0
    private var down = false
    private var middleDown = 0L
    private val handler = Handler(Looper.getMainLooper())

    private fun publish(context: Context, ready: Boolean) {
        isReady = ready
        handler.post { InputService.azsignRootStateChanged() }
        try {
            File(context.getExternalFilesDir(null), "azsign-root-input-status.txt")
                .writeText(if (ready) "ready:pilot-v5" else "unavailable:pilot-v5")
        } catch (e: Exception) { Log.w("AZSignRootInput", "Cannot publish status") }
    }

    @Synchronized fun start(context: Context) {
        if (running || Build.MODEL.uppercase().replace('_', '-') != "MCD-125" ||
            !File(context.filesDir, "azsign-root-input-enabled").isFile) return
        running = true
        commands.clear()
        thread(name = "AZSignRootInput", isDaemon = true) {
            var process: java.lang.Process? = null
            try {
                process = ProcessBuilder(
                    "/system/xbin/su", "0", "/system/bin/app_process",
                    "-Djava.class.path=${context.applicationInfo.sourceDir}",
                    "/system/bin", "com.carriez.flutter_hbb.RootInputServer"
                ).start()
                child = process
                val active = process
                // Drain errors without recording typed keys or process arguments.
                thread(name = "AZSignRootErrors", isDaemon = true) {
                    active.errorStream.bufferedReader().use { input ->
                        while (input.readLine() != null) { /* diagnostics stay in logcat */ }
                    }
                }
                val deadline = SystemClock.uptimeMillis() + 8000
                thread(name = "AZSignRootDeadline", isDaemon = true) {
                    Thread.sleep(8000)
                    if (child === active && !isReady) active.destroy()
                }
                val responses = active.inputStream.bufferedReader()
                val hello = responses.readLine()
                if (hello != "READY AZSIGN_ROOT_INPUT_1" || !running || SystemClock.uptimeMillis() > deadline) {
                    throw IllegalStateException("Root helper not ready")
                }
                publish(context, true)
                Log.i("AZSignRootInput", "Pilot root helper ready")
                val output = active.outputStream.bufferedWriter()
                while (running && active.isAlive) {
                    val command = commands.poll(250, TimeUnit.MILLISECONDS) ?: continue
                    output.write(command)
                    output.newLine()
                    output.flush()
                    if (responses.readLine() != "OK") throw IllegalStateException("Input rejected")
                }
                output.close()
            } catch (e: Exception) {
                Log.w("AZSignRootInput", "Root helper unavailable: ${e.javaClass.simpleName}")
            } finally {
                publish(context, false)
                try {
                    process?.outputStream?.close()
                    if (process?.waitFor(500, TimeUnit.MILLISECONDS) == false) process.destroy()
                } catch (e: Exception) { process?.destroy() }
                child = null
                running = false
                commands.clear()
            }
        }
    }

    fun stop() {
        running = false
        isReady = false
        // EOF lets the helper release a held touch/key before exiting.
        try { child?.outputStream?.close() } catch (e: Exception) { Log.w("AZSignRootInput", "Cannot close helper input") }
        handler.post { InputService.azsignRootStateChanged() }
    }

    private fun send(command: String) {
        if (!isReady) return
        if (!commands.offer(command)) {
            Log.w("AZSignRootInput", "Input queue full; disabling root input")
            stop()
        }
    }

    private fun motion(action: Int) { send("M $action $mouseX $mouseY") }

    @Synchronized fun pointer(kind: Int, mask: Int, x: Int, y: Int) {
        if (!isReady) return
        val width = (SCREEN_INFO.width * SCREEN_INFO.scale).coerceAtLeast(1)
        val height = (SCREEN_INFO.height * SCREEN_INFO.scale).coerceAtLeast(1)
        if (kind == 0) {
            when (mask) {
                TOUCH_PAN_START -> {
                    mouseX = (x * SCREEN_INFO.scale).coerceIn(0, width - 1)
                    mouseY = (y * SCREEN_INFO.scale).coerceIn(0, height - 1)
                    motion(0); down = true
                }
                TOUCH_PAN_UPDATE -> if (down) {
                    mouseX = (mouseX - x * SCREEN_INFO.scale).coerceIn(0, width - 1)
                    mouseY = (mouseY - y * SCREEN_INFO.scale).coerceIn(0, height - 1)
                    motion(2)
                }
                TOUCH_PAN_END -> { if (down) motion(1); down = false }
            }
            return
        }
        if (kind != 1) return
        // RustDesk sends absolute coordinates in MOVE; button messages may be (0,0).
        if (mask == 0 || mask == LEFT_MOVE) {
            mouseX = (x * SCREEN_INFO.scale).coerceIn(0, width - 1)
            mouseY = (y * SCREEN_INFO.scale).coerceIn(0, height - 1)
            if (down) motion(2)
        }
        when (mask) {
            LEFT_DOWN -> { motion(0); down = true }
            LEFT_UP -> { if (down) motion(1); down = false }
            BACK_UP -> send("P ${KeyEvent.KEYCODE_BACK}")
            WHEEL_BUTTON_DOWN -> middleDown = SystemClock.uptimeMillis()
            WHEEL_BUTTON_UP -> {
                val key = if (SystemClock.uptimeMillis() - middleDown > 200) KeyEvent.KEYCODE_APP_SWITCH else KeyEvent.KEYCODE_HOME
                send("P $key")
            }
            WHEEL_DOWN, WHEEL_UP -> {
                if (!down) {
                    motion(0)
                    mouseY = (mouseY + if (mask == WHEEL_DOWN) -120 else 120).coerceIn(0, height - 1)
                    motion(2); motion(1)
                }
            }
        }
    }

    fun key(data: ByteArray) {
        if (!isReady || data.size > 16384) return
        try {
            val proto = MessageOuterClass.KeyEvent.parseFrom(data)
            // Unicode/IME composition is intentionally not supported in this pilot.
            if (proto.hasSeq()) return
            val event = KeyEventConverter.toAndroidKeyEvent(proto)
            if (event.keyCode == KeyEvent.KEYCODE_UNKNOWN) return
            send("K ${event.action} ${event.keyCode} ${event.metaState}")
            if (proto.press) send("K 1 ${event.keyCode} ${event.metaState}")
        } catch (e: Exception) { Log.w("AZSignRootInput", "Invalid key event") }
    }
}
