package app.rhythmstar.rhythmstar_flutter

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Handler
import android.os.HandlerThread
import android.os.Vibrator
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    private lateinit var channel: MethodChannel
    private val audioThread = HandlerThread("RhythmStarAudio")
    private lateinit var audioHandler: Handler
    private val players = LinkedHashMap<String, MediaPlayer>(4, 0.75f, true)
    private var music: MediaPlayer? = null
    private var musicWanted = false
    private var volume = 0.5f
    @Volatile private var active = true
    private var effectStream = 0
    private val effects = mutableMapOf<String, Int>()
    private val readyEffects = mutableSetOf<Int>()
    private var pendingEffect: Int? = null
    private val pressed = mutableMapOf<Int, String>()
    private val soundPool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(
        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    ).build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { focus ->
        if (focus < 0) {
            active = false
            audioHandler.post { stopAudio(false) }
            runOnUiThread { channel.invokeMethod("focus", false) }
        } else if (focus == AudioManager.AUDIOFOCUS_GAIN) {
            runOnUiThread { if (hasWindowFocus()) channel.invokeMethod("focus", true) }
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        volumeControlStream = AudioManager.STREAM_MUSIC
        audioThread.start()
        audioHandler = Handler(audioThread.looper)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rhythmstar/native")
        soundPool.setOnLoadCompleteListener { _, id, status ->
            audioHandler.post {
                if (status == 0) {
                    readyEffects.add(id)
                    if (pendingEffect == id && active) playEffect(id)
                } else reportError("Effect failed to load: $id ($status)")
            }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val prefs = getSharedPreferences("rhythmstar", Context.MODE_PRIVATE)
                    val saves = mutableMapOf<String, String>()
                    for (name in listOf("savedata.dat", "musicdata.dat")) prefs.getString(name, null)?.let { saves[name] = it }
                    audioHandler.post {
                        try {
                            val manifest = assets.open(asset("manifest.json")).bufferedReader().use { JSONObject(it.readText()) }
                            for (name in manifest.keys()) if (name.startsWith("Effect")) {
                                assets.openFd(asset("$name.wav")).use { effects[name] = soundPool.load(it, 1) }
                            }
                            player("MarchChop")
                            player("SpyOut")
                            runOnUiThread { result.success(saves) }
                        } catch (error: Exception) { runOnUiThread { result.error("audio_init", error.toString(), null) } }
                    }
                }
                "commands" -> {
                    val commands = call.arguments as List<*>
                    audioHandler.post {
                        try {
                            for (item in commands) execute(item as List<*>)
                            runOnUiThread { result.success(null) }
                        } catch (error: Exception) { runOnUiThread { result.error("native_command", error.toString(), null) } }
                    }
                }
                "active" -> {
                    val args = call.arguments as Map<*, *>
                    active = args["active"] as Boolean
                    val resume = args["resumeMusic"] as Boolean
                    audioHandler.post {
                        if (!active) stopAudio(false)
                        else if (resume && musicWanted) music?.let { if (!it.isPlaying) it.start() }
                    }
                    result.success(null)
                }
                "dispose" -> { audioHandler.post { stopAudio() }; result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun asset(file: String) = "flutter_assets/assets/audio/$file"
    private fun reportError(message: String) {
        Log.e("RhythmStar", message)
        runOnUiThread { channel.invokeMethod("error", message) }
    }
    private fun player(name: String): MediaPlayer {
        players[name]?.let { return it }
        val player = MediaPlayer()
        try {
            player.setAudioStreamType(AudioManager.STREAM_MUSIC)
            assets.openFd(asset("$name.ogg")).use { player.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
            player.prepare()
            player.setOnErrorListener { _, what, extra -> reportError("Audio $name: $what/$extra"); true }
            player.setOnCompletionListener { if (music === it) musicWanted = false }
        } catch (error: Exception) { player.release(); throw error }
        players[name] = player
        if (players.size > 3) {
            val old = players.entries.firstOrNull { it.value !== music && it.value !== player }
            if (old != null) { players.remove(old.key); old.value.release() }
        }
        return player
    }
    private fun playEffect(id: Int) {
        pendingEffect = null
        soundPool.stop(effectStream)
        effectStream = soundPool.play(id, volume, volume, 1, 0, 1f)
    }
    private fun stopAudio(clearRequested: Boolean = true) {
        if (clearRequested) musicWanted = false
        music?.let { it.setOnSeekCompleteListener(null); if (it.isPlaying) it.pause() }
        soundPool.stop(effectStream)
        pendingEffect = null
    }
    private fun execute(command: List<*>) {
        when (command[0]) {
            "save" -> getSharedPreferences("rhythmstar", Context.MODE_PRIVATE).edit().putString(command[1] as String, command[2] as String).commit()
            "volume" -> {
                volume = (command[1] as Number).toFloat()
                music?.setVolume(volume, volume)
                soundPool.setVolume(effectStream, volume, volume)
            }
            "stop" -> stopAudio()
            "play" -> {
                if (!active) return
                val manager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                if (manager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return
                // Starting a preview or song must not cut off a simultaneous
                // PCM effect. The explicit stop command stops both channels.
                music?.let { it.setOnSeekCompleteListener(null); if (it.isPlaying) it.pause() }
                val next = player(command[1] as String)
                music = next
                musicWanted = true
                next.isLooping = command[2] as Boolean
                next.setVolume(volume, volume)
                // Wait for seek completion so retry/preview always starts at time zero.
                next.setOnSeekCompleteListener { if (active && musicWanted && music === it) it.start() }
                next.seekTo(0)
                Log.i("RhythmStar", "Audio play ${command[1]} loop=${command[2]}")
            }
            "effect" -> {
                if (!active) return
                val id = effects[command[1] as String] ?: error("Missing effect ${command[1]}")
                if (id in readyEffects) playEffect(id) else pendingEffect = id
            }
            "vibrate" -> {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                val ms = (command[1] as Number).toLong()
                if (active && ms > 0) vibrator.vibrate(ms) else vibrator.cancel()
            }
        }
    }
    private fun action(code: Int): String? = when (code) {
        in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> (code - KeyEvent.KEYCODE_0).toString()
        in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> (code - KeyEvent.KEYCODE_NUMPAD_0).toString()
        KeyEvent.KEYCODE_DPAD_UP -> "up"
        KeyEvent.KEYCODE_DPAD_DOWN -> "down"
        KeyEvent.KEYCODE_DPAD_LEFT -> "left"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_BUTTON_A -> "ok"
        KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_SOFT_RIGHT, KeyEvent.KEYCODE_BUTTON_B -> "back"
        KeyEvent.KEYCODE_STAR, KeyEvent.KEYCODE_NUMPAD_MULTIPLY -> "star"
        KeyEvent.KEYCODE_POUND -> "hash"
        KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_SOFT_LEFT -> "ok"
        else -> null
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val key = action(event.keyCode) ?: return super.dispatchKeyEvent(event)
        if (!::channel.isInitialized) return true
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0 && !pressed.containsKey(event.keyCode)) {
            val held = pressed.containsValue(key)
            pressed[event.keyCode] = key
            if (!held) channel.invokeMethod("key", mapOf("key" to key, "down" to true))
        } else if (event.action == KeyEvent.ACTION_UP) {
            pressed.remove(event.keyCode)
            if (!pressed.containsValue(key)) channel.invokeMethod("key", mapOf("key" to key, "down" to false))
        }
        return true
    }
    override fun onPause() {
        pressed.clear()
        active = false
        if (::audioHandler.isInitialized) audioHandler.post { stopAudio(false) }
        super.onPause()
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) {
            pressed.clear()
            if (::channel.isInitialized) channel.invokeMethod("releaseKeys", null)
        }
    }
    override fun onDestroy() {
        if (::audioHandler.isInitialized) audioHandler.post {
            stopAudio(); players.values.forEach { it.release() }; players.clear(); soundPool.release()
            (getSystemService(Context.AUDIO_SERVICE) as AudioManager).abandonAudioFocus(focusListener)
            audioThread.quitSafely()
        }
        super.onDestroy()
    }
}
