package com.smartcapturekit.smart_capture_kit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.SystemClock
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Native side of smart_capture_kit on Android.
 *
 * `recognizeText` runs ML Kit Text Recognition v2 (Latin script, bundled model — no
 * download, works offline) over an image file and returns one entry per recognized
 * line. ML Kit has no Arabic model (see doc/decisions/0001-ocr-engine-selection.md),
 * so `supportedScripts` reports Latin only; the Dart side never asks this engine for
 * Arabic.
 *
 * The response shape is identical to the iOS implementation:
 * `{engineVersion, milliseconds, lines: [{text, confidence?, box: [l, t, r, b],
 * corners?: [x0, y0, ... x3, y3], block}]}`, with coordinates normalized to the
 * upright image (0..1, top-left origin).
 */
class SmartCaptureKitPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var recognizer: TextRecognizer? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "smart_capture_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "supportedScripts" -> result.success(listOf("latin"))
            "recognizeText" -> recognizeText(call, result)
            "disposeTextRecognizer" -> {
                recognizer?.close()
                recognizer = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun recognizeText(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("invalid_arguments", "recognizeText requires 'path'", null)
            return
        }
        // Decoding and EXIF rotation happen off the platform thread; ML Kit then
        // delivers its callbacks on the main thread, where replying is safe.
        executor.execute {
            val bitmap: Bitmap
            try {
                bitmap = decodeUpright(path)
            } catch (e: Exception) {
                postError(result, "image_unreadable", "Could not decode $path: ${e.message}")
                return@execute
            }
            val engine = recognizer ?: TextRecognition
                .getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                .also { recognizer = it }
            val start = SystemClock.elapsedRealtime()
            engine.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { text ->
                    val w = bitmap.width.toDouble()
                    val h = bitmap.height.toDouble()
                    val lines = mutableListOf<Map<String, Any?>>()
                    text.textBlocks.forEachIndexed { blockIndex, block ->
                        for (line in block.lines) {
                            val box = line.boundingBox ?: continue
                            lines.add(
                                mapOf(
                                    "text" to line.text,
                                    "confidence" to line.confidence.toDouble(),
                                    "box" to listOf(box.left / w, box.top / h, box.right / w, box.bottom / h),
                                    "corners" to line.cornerPoints?.flatMap { listOf(it.x / w, it.y / h) },
                                    "block" to blockIndex,
                                )
                            )
                        }
                    }
                    result.success(
                        mapOf(
                            "engineVersion" to "text-recognition 16.0.1",
                            "milliseconds" to (SystemClock.elapsedRealtime() - start),
                            "lines" to lines,
                        )
                    )
                }
                .addOnFailureListener { e ->
                    result.error("ocr_failed", e.message ?: "ML Kit text recognition failed", null)
                }
        }
    }

    /** Decodes [path] and applies its EXIF orientation so boxes match the upright image. */
    private fun decodeUpright(path: String): Bitmap {
        val bitmap = BitmapFactory.decodeFile(path)
            ?: throw IllegalArgumentException("not a decodable image")
        val degrees = when (ExifInterface(File(path)).getAttributeInt(
            ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
        )) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (degrees == 0f) return bitmap
        val matrix = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun postError(result: Result, code: String, message: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            result.error(code, message, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        recognizer?.close()
        recognizer = null
        executor.shutdown()
    }
}
