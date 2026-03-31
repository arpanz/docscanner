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
            
            if (activity.pendingCameraStart) {
                activity.pendingCameraStart = false
                activity.startCamera(activity.pendingCameraResult)
                activity.pendingCameraResult = null
            }
            
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
    
    var pendingCameraStart: Boolean = false
    var pendingCameraResult: MethodChannel.Result? = null

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
                        startCamera(result)
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
                    "cropImage" -> {
                        val path = call.argument<String>("path") ?: ""
                        val corners = call.argument<List<Double>>("corners") ?: emptyList()
                        cropImage(path, corners, result)
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

    fun startCamera(result: MethodChannel.Result? = null) {
        // Check camera permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            pendingCameraResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                REQUEST_CAMERA_PERMISSION
            )
            return
        }

        runOnUiThread {
            val currentPreviewView = previewView
            if (currentPreviewView == null) {
                // PreviewView not yet created by PlatformView, defer it
                pendingCameraStart = true
                pendingCameraResult = result
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
            
            result?.success(null)
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
        // captureDocument uses callbacks, so we just initiate on main thread
        scannerEngine?.captureDocument(corners) { imagePath ->
            CoroutineScope(Dispatchers.Main).launch {
                result.success(imagePath)
            }
        }
    }

    private fun cropImage(path: String, corners: List<Double>, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val croppedPath = scannerEngine?.cropImage(path, corners)
                CoroutineScope(Dispatchers.Main).launch {
                    result.success(croppedPath)
                }
            } catch (e: Exception) {
                CoroutineScope(Dispatchers.Main).launch {
                    result.error("CROP_ERROR", e.message, null)
                }
            }
        }
    }

    private fun enhanceImage(path: String, mode: String, result: MethodChannel.Result) {
        // Run heavy image processing on IO thread
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val enhancedPath = scannerEngine?.enhanceAndSave(path, mode)
                CoroutineScope(Dispatchers.Main).launch {
                    result.success(enhancedPath)
                }
            } catch (e: Exception) {
                CoroutineScope(Dispatchers.Main).launch {
                    result.error("ENHANCE_ERROR", e.message, null)
                }
            }
        }
    }

    private fun buildPdf(images: List<String>, title: String, result: MethodChannel.Result) {
        // Run heavy PDF generation on IO thread
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val pdfPath = scannerEngine?.buildPdfNative(images, title)
                CoroutineScope(Dispatchers.Main).launch {
                    result.success(pdfPath)
                }
            } catch (e: Exception) {
                CoroutineScope(Dispatchers.Main).launch {
                    result.error("PDF_ERROR", e.message, null)
                }
            }
        }
    }

    private fun extractText(path: String, result: MethodChannel.Result) {
        // Run OCR on IO thread
        CoroutineScope(Dispatchers.IO).launch {
            scannerEngine?.extractText(path) { text ->
                CoroutineScope(Dispatchers.Main).launch {
                    result.success(text)
                }
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
                startCamera(pendingCameraResult)
                pendingCameraResult = null
            } else {
                // Permission denied - notify Flutter
                pendingCameraResult?.error("PERMISSION_DENIED", "Camera permission is required", null)
                pendingCameraResult = null
                edgeEventSink?.error(
                    "PERMISSION_DENIED",
                    "Camera permission is required for scanning",
                    null
                )
            }
        }
    }
}
