"""Run the real capture callback and stopCapture on JVM with controlled fake images.
KOTLIN_TEST_CLASSPATH supplies an existing Kotlin compiler and runtime; no downloads.
"""
from pathlib import Path
import os, subprocess, tempfile

root = Path(__file__).resolve().parents[2]
base = subprocess.check_output(['git', 'show', '1.4.9:flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt'], cwd=root, text=True)
cp = os.environ['KOTLIN_TEST_CLASSPATH']

def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

fixture = r'''
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class Surface { fun release() {}; fun setSurface(s: Surface?) {} }
object Log { fun d(tag: String, text: String) {} }
object PixelFormat { const val RGBA_8888 = 1 }
object SCREEN_INFO { const val width = 1920; const val height = 1080 }
object FFI { fun setFrameRawEnable(kind: String, enabled: Boolean) {}; fun onVideoFrameUpdate(b: ByteBuffer) {} }
object MainActivity { val rdClipboardManager: Clipboard? = null }
class Clipboard { fun setCaptureStarted(started: Boolean) {} }
class Encoder { fun signalEndOfInputStream() {}; fun stop() {}; fun release() {} }
class Audio { fun tryReleaseAudio() {} }
class Plane { val buffer = ByteBuffer.allocate(4) }
class FakeImage : AutoCloseable {
    @Volatile var closed = false
    val planes: Array<Plane> get() {
        ImageReader.entered.countDown()
        check(ImageReader.resume.await(5, TimeUnit.SECONDS))
        check(!closed) { "Image invalidated while getPlanes was executing" }
        return arrayOf(Plane())
    }
    override fun close() { closed = true }
}
class ImageReader {
    companion object {
        var entered = CountDownLatch(1)
        var resume = CountDownLatch(1)
        fun newInstance(w: Int, h: Int, f: Int, n: Int) = ImageReader()
    }
    var calls = 0
    val image = FakeImage()
    val surface = Surface()
    lateinit var listener: (ImageReader) -> Unit
    fun setOnImageAvailableListener(l: (ImageReader) -> Unit, handler: Any?) { listener = l }
    fun acquireLatestImage(): FakeImage { calls++; return image }
    fun close() { image.close() }
}
class MainService {
    var imageReader: ImageReader? = null
    val useVP9 = false
    val logTag = "test"
    val serviceHandler: Any? = null
    var _isStart = true
    val isStart get() = _isStart
    var _isAudioStart = false
    val reuseVirtualDisplay = false
    var virtualDisplay: Surface? = null
    var videoEncoder: Encoder? = null
    var surface: Surface? = null
    val audioRecordHandle = Audio()
    fun prepare() = createSurface()
    __CREATE__
    @Synchronized
    __STOP__
}
fun main(args: Array<String>) {
    val fixed = args[0] == "fixed"
    val service = MainService()
    service.prepare()
    val reader = service.imageReader!!
    val failure = AtomicReference<Throwable?>()
    val frame = Thread { try { reader.listener(reader) } catch (t: Throwable) { failure.set(t) } }
    frame.start()
    check(ImageReader.entered.await(5, TimeUnit.SECONDS))
    val stopStarted = CountDownLatch(1)
    val stop = Thread { stopStarted.countDown(); service.stopCapture() }
    stop.start()
    check(stopStarted.await(5, TimeUnit.SECONDS))
    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
    while (stop.isAlive && stop.state != Thread.State.BLOCKED && System.nanoTime() < deadline) Thread.yield()
    if (fixed) {
        check(stop.state == Thread.State.BLOCKED) { "teardown did not wait for frame" }
        check(!reader.image.closed) { "reader closed during getPlanes" }
    } else {
        stop.join(5000)
        check(reader.image.closed) { "baseline race not reproduced" }
    }
    ImageReader.resume.countDown()
    frame.join(5000); stop.join(5000)
    check(!frame.isAlive && !stop.isAlive) { "deadlock" }
    failure.get()?.let { throw it }
    check(reader.image.closed)
    if (fixed) {
        // Already queued callback from a retired reader must not acquire an image,
        // even after a new capture has started.
        service._isStart = true
        service.prepare()
        val calls = reader.calls
        reader.listener(reader)
        check(reader.calls == calls) { "retired reader was accessed" }
    }
    println(if (fixed) "PASS: teardown waits, frame releases, retired callback ignored" else "BASELINE: reader closes during getPlanes (exception swallowed by original callback)")
}
'''
with tempfile.TemporaryDirectory(prefix='azsign-capture-test-') as temp:
    directory = Path(temp)
    target = directory / 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt'
    target.parent.mkdir(parents=True)
    target.write_text(base)
    subprocess.run(['python3', str(Path(__file__).with_name('apply.py')), temp], check=True)
    patched = target.read_text()
    subprocess.run(['python3', str(Path(__file__).with_name('apply.py')), temp], check=True)
    assert target.read_text() == patched, 'patch must be idempotent'
    assert '@Synchronized\n    fun startCapture()' in patched
    assert '@Synchronized\n    private fun updateScreenInfo(' in patched
    for name, source in [('baseline', base), ('fixed', patched)]:
        kotlin = fixture.replace('__CREATE__', method(source, 'private fun createSurface()')).replace('__STOP__', method(source, 'fun stopCapture()'))
        source_file = directory / 'CaptureTest.kt'
        source_file.write_text(kotlin)
        classes = directory / name
        subprocess.run(['java', '-cp', cp, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect', '-nowarn', '-classpath', cp, '-d', str(classes), str(source_file)], check=True)
        subprocess.run(['java', '-cp', f'{classes}{os.pathsep}{cp}', 'CaptureTestKt', name], check=True, timeout=15)
    print('Patch application and Kotlin compilation passed. Android/firmware not simulated.')
