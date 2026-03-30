package com.example.docscanner

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Main Flutter Activity with native scanner bridge.
 * 
 * Provides MethodChannel for commands and EventChannel for live edge detection stream.
 */
class MainActivity : FlutterActivity() {
    
    /**
     * Factory for creating native camera preview PlatformView.
     */
    private class CameraPreviewFactory(
        private val activity: MainActivity
    ) : PlatformViewFactory(io.flutter.plugin.common.StandardMessageCodec.INSTANCE) {
        
        override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
            val container = FrameLayout(context!!)
            val previewView = PreviewView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                scaleType = PreviewView.ScaleType.FILL_CENTER
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            }
            container.addView(previewView)
            
            // Store reference in activity
            activity.previewView = previewView
            
            return object : PlatformView {
                override fun getView(): View = container
                
                override fun dispose() {
                    activity.scannerEngine?.stopCamera()
                }
            }
        }
    }
    companion object {
        private const val CHANNEL_SCANNER = "com.example.docscanner/scanner"
        private const val CHANNEL_EDGES = "com.example.docscanner/edges"
        private const val REQUEST_CAMERA_PERMISSION = 1001
    }

    private var scannerEngine: ScannerEngine? = null
    private var edgeEventSink: EventChannel.EventSink? = null
    private var previewView: PreviewView? = null
    private var hasFlashTorch: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize scanner engine
        scannerEngine = ScannerEngine(this, this as LifecycleOwner)

        // Register PlatformView factory for native camera preview
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.example.docscanner/camera_preview",
            CameraPreviewFactory(this)
        )

        // Setup MethodChannel for commands
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SCANNER)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCamera" -> {
                        startCamera()
                        result.success(null)
                    }
                    "stopCamera" -> {
                        stopCamera()
                        result.success(null)
                    }
                    "setFlash" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setFlash(enabled, result)
                    }
                    "captureDocument" -> {
                        val corners = call.argument<List<Double>>("corners") ?: emptyList()
                        captureDocument(corners, result)
                    }
                    "enhanceImage" -> {
                        val path = call.argument<String>("path") ?: ""
                        val mode = call.argument<String>("mode") ?: "photo"
                        enhanceImage(path, mode, result)
                    }
                    "buildPdf" -> {
                        val images = call.argument<List<String>>("images") ?: emptyList()
                        val title = call.argument<String>("title") ?: "Document"
                        buildPdf(images, title, result)
                    }
                    "extractText" -> {
                        val path = call.argument<String>("path") ?: ""
                        extractText(path, result)
                    }
                    else -> result.notImplemented()
                }
            }

        // Setup EventChannel for live edge detection stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_EDGES)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    edgeEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    edgeEventSink = null
                }
            })
    }

    override fun onDestroy() {
        super.onDestroy()
        scannerEngine?.stopCamera()
        scannerEngine = null
    }

    private fun startCamera() {
        // Check camera permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_CAMERA_PERMISSION
            )
            return
        }

        // Start camera with the PreviewView from PlatformView
        runOnUiThread {
            val currentPreviewView = previewView
            if (currentPreviewView == null) {
                // PreviewView not yet created by PlatformView
                edgeEventSink?.error(
                    "PREVIEW_NOT_READY",
                    "Camera preview is not ready yet",
                    null
                )
                return@runOnUiThread
            }
            
            scannerEngine?.startCamera(currentPreviewView)

            // Setup edge detection callback to stream to Flutter with frame dimensions
            scannerEngine?.onEdgeDetected = { corners, frameWidth, frameHeight ->
                runOnUiThread {
                    // Send as map with corners and frame dimensions
                    val data = mapOf(
                        "corners" to corners,
                        "frameWidth" to frameWidth,
                        "frameHeight" to frameHeight
                    )
                    edgeEventSink?.success(data)
                }
            }

            scannerEngine?.onError = { error ->
                runOnUiThread {
                    edgeEventSink?.error("SCANNER_ERROR", error, null)
                }
            }
        }
    }

    private fun stopCamera() {
        runOnUiThread {
            scannerEngine?.stopCamera()
            previewView?.let {
                // Don't remove the view, just stop camera
            }
        }
    }

    private fun setFlash(enabled: Boolean, result: MethodChannel.Result) {
        runOnUiThread {
            try {
                scannerEngine?.setFlashTorch(enabled)
                hasFlashTorch = enabled
                result.success(null)
            } catch (e: Exception) {
                result.error("FLASH_ERROR", e.message, null)
            }
        }
    }

    private fun captureDocument(corners: List<Double>, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.Main).launch {
            scannerEngine?.captureDocument(corners) { imagePath ->
                result.success(imagePath)
            }
        }
    }

    private fun enhanceImage(path: String, mode: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val enhancedPath = scannerEngine?.enhanceAndSave(path, mode)
                result.success(enhancedPath)
            } catch (e: Exception) {
                result.error("ENHANCE_ERROR", e.message, null)
            }
        }
    }

    private fun buildPdf(images: List<String>, title: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val pdfPath = scannerEngine?.buildPdfNative(images, title)
                result.success(pdfPath)
            } catch (e: Exception) {
                result.error("PDF_ERROR", e.message, null)
            }
        }
    }

    private fun extractText(path: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.Main).launch {
            scannerEngine?.extractText(path) { text ->
                result.success(text)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CAMERA_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startCamera()
            } else {
                // Permission denied - notify Flutter
                edgeEventSink?.error(
                    "PERMISSION_DENIED",
                    "Camera permission is required for scanning",
                    null
                )
            }
        }
    }
}
