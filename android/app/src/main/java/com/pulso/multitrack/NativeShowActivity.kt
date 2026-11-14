package com.pulso.multitrack

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.nio.ByteOrder
import kotlin.math.pow

internal object NativeAudio {
    init { System.loadLibrary("pulso_android") }
    external fun open(rate: Int, left: FloatArray, right: FloatArray): Long
    external fun close(handle: Long)
    external fun command(handle: Long, action: Int, value: Float = 0f)
    external fun position(handle: Long): Float
}

class NativeShowActivity : ComponentActivity() {
    private var handle by mutableLongStateOf(0)
    private var loading by mutableStateOf(false)
    private var title by mutableStateOf("Abre una pista FLAC")
    private var error by mutableStateOf<String?>(null)
    private var master by mutableFloatStateOf(0f)

    private val picker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) load(uri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("PULSO · Show", style = MaterialTheme.typography.headlineMedium)
                        Text(title)
                        Button(enabled = !loading, onClick = { picker.launch(arrayOf("audio/*", "application/octet-stream")) }) {
                            Text(if (loading) "Cargando…" else "Abrir FLAC")
                        }
                        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                        var seconds by remember { mutableFloatStateOf(0f) }
                        LaunchedEffect(handle) {
                            while (true) {
                                seconds = NativeAudio.position(handle)
                                delay(80)
                            }
                        }
                        Text("%d:%02d".format(seconds.toInt() / 60, seconds.toInt() % 60))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf("Reproducir", "Pausa", "Detener").forEachIndexed { index, label ->
                                Button(enabled = handle != 0L && !loading,
                                    onClick = { NativeAudio.command(handle, index) }) { Text(label) }
                            }
                        }
                        Text("Master %.1f dB".format(master))
                        Slider(value = master, valueRange = -60f..10f, enabled = handle != 0L,
                            onValueChange = {
                                master = it
                                NativeAudio.command(handle, 3, 10f.pow(it / 20f))
                            })
                    }
                }
            }
        }
    }

    private fun load(uri: Uri) {
        loading = true
        error = null
        lifecycleScope.launch {
            try {
                val pcm = withContext(Dispatchers.IO) { decode(uri) }
                // Solo el hilo de UI instala y destruye handles del reproductor.
                NativeAudio.close(handle)
                handle = 0
                handle = NativeAudio.open(pcm.rate, pcm.left, pcm.right)
                check(handle != 0L) { "No se pudo abrir la salida de audio" }
                NativeAudio.command(handle, 3, 10f.pow(master / 20f))
                title = uri.lastPathSegment?.substringAfterLast('/') ?: "Pista local"
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "No se pudo cargar la pista"
            } finally {
                loading = false
            }
        }
    }

    override fun onStop() {
        if (handle != 0L) NativeAudio.command(handle, 1)
        super.onStop()
    }

    override fun onDestroy() {
        if (handle != 0L) NativeAudio.close(handle)
        handle = 0
        super.onDestroy()
    }

    private data class Pcm(val rate: Int, val left: FloatArray, val right: FloatArray)

    private fun decode(uri: Uri): Pcm {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(this, uri, null)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME) == "audio/flac"
            } ?: error("Selecciona un archivo FLAC")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType("audio/flac")
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var left = FloatArray(16384)
            var right = FloatArray(left.size)
            var frames = 0
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var ended = false
            var idle = 0
            while (!ended) {
                if (!inputEnded) {
                    val i = codec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val input = checkNotNull(codec.getInputBuffer(i))
                        input.clear()
                        val size = extractor.readSampleData(input, 0)
                        inputEnded = size < 0
                        codec.queueInputBuffer(i, 0, size.coerceAtLeast(0),
                            extractor.sampleTime.coerceAtLeast(0),
                            if (inputEnded) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                        if (!inputEnded) extractor.advance()
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val output = codec.outputFormat
                    rate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (output.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        encoding = output.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    }
                }
                if (o < 0) {
                    check(++idle < 1000) { "El decodificador FLAC dejó de responder" }
                    continue
                }
                idle = 0
                check(channels in 1..2) { "Usa un FLAC mono o estéreo" }
                val output = checkNotNull(codec.getOutputBuffer(o)).order(ByteOrder.nativeOrder())
                output.limit(info.offset + info.size)
                output.position(info.offset)
                val bytes = when (encoding) {
                    AudioFormat.ENCODING_PCM_FLOAT, AudioFormat.ENCODING_PCM_32BIT -> 4
                    AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
                    AudioFormat.ENCODING_PCM_16BIT -> 2
                    else -> error("Formato PCM no compatible")
                }
                fun sample(): Float = when (encoding) {
                    AudioFormat.ENCODING_PCM_FLOAT -> output.float
                    AudioFormat.ENCODING_PCM_32BIT -> output.int / 2147483648f
                    AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                        val value = (output.get().toInt() and 255) or
                            ((output.get().toInt() and 255) shl 8) or (output.get().toInt() shl 16)
                        value / 8388608f
                    }
                    else -> output.short / 32768f
                }
                val count = output.remaining() / (bytes * channels)
                check(frames + count <= 24_000_000) { "La pista supera el límite de memoria del prototipo" }
                if (frames + count > left.size) {
                    val capacity = maxOf(frames + count, left.size * 2).coerceAtMost(24_000_000)
                    left = left.copyOf(capacity)
                    right = right.copyOf(capacity)
                }
                repeat(count) {
                    left[frames] = sample()
                    right[frames] = if (channels == 2) sample() else left[frames]
                    frames++
                }
                ended = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                codec.releaseOutputBuffer(o, false)
            }
            check(frames > 0) { "El FLAC no contiene audio" }
            return Pcm(rate, left.copyOf(frames), right.copyOf(frames))
        } finally {
            decoder?.release()
            extractor.release()
        }
    }
}
