package com.example.docscanner

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Core native scanning engine using CameraX + OpenCV.
 *
 * This class owns:
 * - Camera preview and frame analysis
 * - Real-time edge detection via OpenCV
 * - Perspective correction (warpPerspective)
 * - Image enhancement filters
 * - Native PDF generation
 * - OCR via ML Kit
 */
class ScannerEngine(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner
) {
    companion object {
        private const val TAG = "ScannerEngine"

        // A4 dimensions at 300 DPI (standard scan quality)
        private const val A4_WIDTH = 2480
        private const val A4_HEIGHT = 3508

        // Output size for perspective-corrected images (max dimension)
        private const val MAX_OUTPUT_SIZE = 3000

        // Enhancement mode constants
        const val MODE_PHOTO = "photo"
        const val MODE_MAGIC_COLOR = "magic_color"
        const val MODE_GRAYSCALE = "grayscale"
        const val MODE_BLACK_WHITE = "black_white"
        const val MODE_WHITEBOARD = "whiteboard"
    }

    private var camera: Camera? = null
    private var preview: Preview? = null
    private var imageAnalyzer: ImageAnalysis? = null
    private var imageCapture: ImageCapture? = null
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val openCvInitialized: Boolean = initializeOpenCv()
    @Volatile
    private var openCvErrorReported = false

    // Store the last analyzed frame dimensions atomically with corner data
    private var lastAnalyzedFrameWidth: Int = 0
    private var lastAnalyzedFrameHeight: Int = 0

    // ── Temporal smoothing (EMA) state ──────────────────────────────────────
    private var smoothedCorners: List<Double>? = null
    private var noDetectionCount = 0
    private val emaAlpha = 0.30
    private val snapDistanceThreshold = 50.0  // px – snap immediately on big jumps
    private val maxNoDetectionFrames = 12      // keep overlay visible longer on brief misses

    // Callbacks
    var onFrameAnalyzed: ((Bitmap, List<Double>, Int, Int) -> Unit)? = null
    var onEdgeDetected: ((List<Double>, Int, Int) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    private fun initializeOpenCv(): Boolean {
        return try {
            if (OpenCVLoader.initDebug()) {
                Log.i(TAG, "OpenCV initialized via OpenCVLoader")
                true
            } else {
                Log.w(TAG, "OpenCVLoader.initDebug() failed, trying manual load")
                System.loadLibrary("opencv_java4")
                Log.i(TAG, "OpenCV initialized via System.loadLibrary")
                true
            }
        } catch (t: Throwable) {
            Log.e(TAG, "OpenCV initialization failed", t)
            false
        }
    }

    private fun ensureOpenCvReady(): Boolean {
        if (openCvInitialized) return true
        if (!openCvErrorReported) {
            openCvErrorReported = true
            val message = "OpenCV native library is unavailable. Rebuild and reinstall the app."
            Log.e(TAG, message)
            onError?.invoke(message)
        }
        return false
    }

    fun startCamera(
        previewView: PreviewView,
        enableFrameAnalysis: Boolean = true
    ) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()

                preview = Preview.Builder()
                    .build()
                    .also { it.setSurfaceProvider(previewView.surfaceProvider) }

                if (enableFrameAnalysis && ensureOpenCvReady()) {
                    imageAnalyzer = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                        .setTargetResolution(android.util.Size(1280, 720))
                        .build()
                        .also { analysis ->
                            analysis.setAnalyzer(cameraExecutor) { imageProxy ->
                                try {
                                    val bitmap = imageProxy.toBitmap()
                                    val corners = detectDocumentContour(bitmap)
                                    val frameWidth = bitmap.width
                                    val frameHeight = bitmap.height
                                    lastAnalyzedFrameWidth = frameWidth
                                    lastAnalyzedFrameHeight = frameHeight

                                    if (corners != null) {
                                        noDetectionCount = 0
                                        val rawList = flattenCorners(corners)
                                        val emitted = applyTemporalSmoothing(rawList)
                                        onEdgeDetected?.invoke(emitted, frameWidth, frameHeight)
                                        onFrameAnalyzed?.invoke(bitmap, emitted, frameWidth, frameHeight)
                                    } else {
                                        noDetectionCount++
                                        if (noDetectionCount >= maxNoDetectionFrames) {
                                            smoothedCorners = null
                                        }
                                        smoothedCorners?.let { prev ->
                                            onEdgeDetected?.invoke(prev, frameWidth, frameHeight)
                                        }
                                    }
                                } catch (t: Throwable) {
                                    Log.e(TAG, "Frame analysis error", t)
                                } finally {
                                    imageProxy.close()
                                }
                            }
                        }
                } else if (enableFrameAnalysis) {
                    Log.w(TAG, "Frame analysis disabled because OpenCV is not ready")
                }

                imageCapture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                    .setTargetResolution(android.util.Size(MAX_OUTPUT_SIZE, MAX_OUTPUT_SIZE))
                    .build()

                cameraProvider.unbindAll()
                val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
                camera = cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    preview,
                    imageAnalyzer,
                    imageCapture
                )

                Log.i(TAG, "Camera started successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Camera start failed", e)
                onError?.invoke("Failed to start camera: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun stopCamera() {
        try {
            val cameraProvider = ProcessCameraProvider.getInstance(context).get()
            cameraProvider.unbindAll()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping camera", e)
        }
        camera = null
        preview = null
        imageAnalyzer = null
        imageCapture = null
    }

    fun setFlashTorch(enabled: Boolean) {
        camera?.let {
            if (it.cameraInfo.hasFlashUnit()) {
                it.cameraControl.enableTorch(enabled)
            }
        }
    }

    /**
     * Capture a raw (uncropped) high-resolution frame without any perspective correction.
     * Used to display the full image in ManualCropEditor before the user adjusts corners.
     */
    fun captureRaw(onComplete: (String) -> Unit) {
        val imageCapture = imageCapture ?: run {
            onError?.invoke("Camera not initialized")
            return
        }
        val outputFile = File(context.filesDir, "raw_${System.currentTimeMillis()}.jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()

        imageCapture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    onComplete(outputFile.absolutePath)
                }
                override fun onError(exception: ImageCaptureException) {
                    Log.e(TAG, "Raw capture failed", exception)
                    onError?.invoke("Capture failed: ${exception.message}")
                }
            }
        )
    }

    /**
     * Capture a high-resolution image and apply perspective correction.
     *
     * @param corners The 4 corner points of the detected document (in analysis frame coordinates)
     * @param onCaptureComplete Callback with the saved file path
     */
    fun captureDocument(corners: List<Double>, onCaptureComplete: (String) -> Unit) {
        if (corners.size < 8) {
            onError?.invoke("Invalid corners data")
            return
        }

        val imageCapture = imageCapture ?: run {
            onError?.invoke("Camera not initialized")
            return
        }

        val outputDir = context.filesDir
        val outputFile = File(outputDir, "scan_${System.currentTimeMillis()}.jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()

        imageCapture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    val capturedBitmap = BitmapFactory.decodeFile(outputFile.absolutePath)
                        ?: run {
                            onError?.invoke("Failed to decode captured image")
                            return
                        }

                    try {
                        val scaleX = capturedBitmap.width.toDouble() / lastAnalyzedFrameWidth
                        val scaleY = capturedBitmap.height.toDouble() / lastAnalyzedFrameHeight

                        val scaledCorners = corners.chunked(2).map { (x, y) ->
                            listOf(x * scaleX, y * scaleY)
                        }.flatten()

                        val cornerPoints = deflattenCorners(scaledCorners)
                        val correctedBitmap = perspectiveCorrect(capturedBitmap, cornerPoints)
                        correctedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, FileOutputStream(outputFile))
                        correctedBitmap.recycle()
                        onCaptureComplete(outputFile.absolutePath)
                    } catch (e: Exception) {
                        Log.e(TAG, "Perspective correction failed", e)
                        onError?.invoke("Failed to process image: ${e.message}")
                    } finally {
                        capturedBitmap.recycle()
                    }
                }

                override fun onError(exception: ImageCaptureException) {
                    Log.e(TAG, "Capture failed", exception)
                    onError?.invoke("Capture failed: ${exception.message}")
                }
            }
        )
    }

    fun cropImage(imagePath: String, corners: List<Double>): String {
        if (corners.size < 8) throw IllegalArgumentException("Invalid corners data")

        val inputBitmap = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalArgumentException("Cannot decode image: $imagePath")

        val croppedBitmap = try {
            perspectiveCorrect(inputBitmap, deflattenCorners(corners))
        } finally {
            inputBitmap.recycle()
        }

        val outputFile = File(context.filesDir, "cropped_${System.currentTimeMillis()}.jpg")
        try {
            FileOutputStream(outputFile).use { croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
            return outputFile.absolutePath
        } finally {
            croppedBitmap.recycle()
        }
    }

    /**
     * Detect document contour in a bitmap using OpenCV.
     * Returns 4 corner points if a document is found, null otherwise.
     */
    fun detectDocumentContour(bitmap: Bitmap): MatOfPoint2f? {
        if (!ensureOpenCvReady()) return null

        var mat: Mat? = null
        var gray: Mat? = null
        var blurred: Mat? = null
        var edges: Mat? = null
        val contours = ArrayList<MatOfPoint>()

        try {
            mat = Mat()
            Utils.bitmapToMat(bitmap, mat)

            gray = Mat()
            blurred = Mat()
            edges = Mat()

            Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)

            val lowerThreshold = computeAdaptiveCannyThreshold(blurred)
            val upperThreshold = lowerThreshold * 2.5
            Imgproc.Canny(blurred, edges, lowerThreshold, upperThreshold)

            val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
            val closedEdges = Mat()
            Imgproc.morphologyEx(edges, closedEdges, Imgproc.MORPH_CLOSE, kernel)
            kernel.release()

            val hierarchy = Mat()
            Imgproc.findContours(
                closedEdges, contours, hierarchy,
                Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE
            )
            hierarchy.release()
            closedEdges.release()

            // Minimum area = 3.5% of frame — detects documents that don't fill the frame
            val minArea = (mat.width() * mat.height()) * 0.035
            return contours
                .filter { Imgproc.contourArea(it) > minArea }
                .sortedByDescending { Imgproc.contourArea(it) }
                .firstNotNullOfOrNull { contour -> approxQuad(contour) }
        } catch (t: Throwable) {
            Log.e(TAG, "Edge detection failed", t)
            return null
        } finally {
            mat?.release()
            gray?.release()
            blurred?.release()
            edges?.release()
            contours.forEach { it.release() }
        }
    }

    private fun computeAdaptiveCannyThreshold(gray: Mat): Double {
        val meanMat = MatOfDouble()
        val stdDevMat = MatOfDouble()
        Core.meanStdDev(gray, meanMat, stdDevMat)
        val stdDev = stdDevMat.toArray()[0]
        meanMat.release()
        stdDevMat.release()
        val contrastFactor = stdDev / 50.0
        return (100.0 * contrastFactor).coerceIn(50.0, 150.0)
    }

    private fun approxQuad(contour: MatOfPoint): MatOfPoint2f? {
        val contour2f = MatOfPoint2f(*contour.toArray().map { p ->
            Point(p.x.toDouble(), p.y.toDouble())
        }.toTypedArray())

        val peri = Imgproc.arcLength(contour2f, true)
        val approx = MatOfPoint2f()
        // Looser epsilon (0.03) handles slightly curved/warped document edges
        Imgproc.approxPolyDP(contour2f, approx, 0.03 * peri, true)
        contour2f.release()

        if (approx.total() != 4L) {
            approx.release()
            return null
        }

        val ordered = orderPoints(approx)
        if (!isValidQuadrilateral(ordered)) {
            ordered.release()
            return null
        }
        return ordered
    }

    private fun isValidQuadrilateral(points: MatOfPoint2f): Boolean {
        val pts = points.toArray()
        if (pts.size < 4) return false

        val crossProducts = mutableListOf<Double>()
        for (i in 0..3) {
            val p1 = pts[i]; val p2 = pts[(i + 1) % 4]; val p3 = pts[(i + 2) % 4]
            val v1x = p2.x - p1.x; val v1y = p2.y - p1.y
            val v2x = p3.x - p2.x; val v2y = p3.y - p2.y
            crossProducts.add(v1x * v2y - v1y * v2x)
        }
        val allPositive = crossProducts.all { it > 0 }
        val allNegative = crossProducts.all { it < 0 }
        if (!allPositive && !allNegative) return false

        val widthTop = distance(pts[0], pts[1])
        val widthBottom = distance(pts[3], pts[2])
        val heightLeft = distance(pts[0], pts[3])
        val heightRight = distance(pts[1], pts[2])
        val avgWidth = (widthTop + widthBottom) / 2
        val avgHeight = (heightLeft + heightRight) / 2
        if (avgWidth > 0 && avgHeight > 0) {
            val aspectRatio = avgWidth / avgHeight
            if (aspectRatio > 10.0 || aspectRatio < 0.1) return false
        }

        if (Imgproc.contourArea(points) < 1000) return false
        return true
    }

    private fun orderPoints(points: MatOfPoint2f): MatOfPoint2f {
        val pts = points.toArray()
        val sorted = pts.sortedWith(compareBy({ it.y }, { it.x }))
        val topTwo = sorted.take(2).sortedBy { it.x }
        val bottomTwo = sorted.takeLast(2).sortedBy { it.x }
        return MatOfPoint2f(
            topTwo[0], topTwo[1],
            bottomTwo[1], bottomTwo[0]
        )
    }

    fun perspectiveCorrect(bitmap: Bitmap, corners: MatOfPoint2f): Bitmap {
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)
        val result = Mat()
        var dstPoints = MatOfPoint2f()
        var transform = Mat()

        try {
            val srcPoints = corners.toArray()
            val widthTop = distance(srcPoints[0], srcPoints[1])
            val widthBottom = distance(srcPoints[3], srcPoints[2])
            val maxWidth = maxOf(widthTop, widthBottom).toInt()
            val heightLeft = distance(srcPoints[0], srcPoints[3])
            val heightRight = distance(srcPoints[1], srcPoints[2])
            val maxHeight = maxOf(heightLeft, heightRight).toInt()
            val (outputWidth, outputHeight) = limitSize(maxWidth, maxHeight)

            dstPoints.release()
            dstPoints = MatOfPoint2f(
                Point(0.0, 0.0),
                Point(outputWidth.toDouble(), 0.0),
                Point(outputWidth.toDouble(), outputHeight.toDouble()),
                Point(0.0, outputHeight.toDouble())
            )
            transform.release()
            transform = Imgproc.getPerspectiveTransform(corners, dstPoints)
            Imgproc.warpPerspective(mat, result, transform, Size(outputWidth.toDouble(), outputHeight.toDouble()))

            val outputBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(result, outputBitmap)
            return outputBitmap
        } catch (e: Exception) {
            Log.e(TAG, "Perspective correction failed", e)
            throw e
        } finally {
            mat.release(); result.release(); dstPoints.release(); transform.release()
        }
    }

    fun enhance(bitmap: Bitmap, mode: String): Bitmap {
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)
        return when (mode) {
            MODE_PHOTO -> bitmap
            MODE_MAGIC_COLOR -> applyMagicColor(mat)
            MODE_GRAYSCALE -> applyGrayscale(mat)
            MODE_BLACK_WHITE -> applyBlackWhite(mat)
            MODE_WHITEBOARD -> applyWhiteboard(mat)
            else -> bitmap
        }
    }

    fun enhanceAndSave(imagePath: String, mode: String): String {
        val inputBitmap = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalArgumentException("Cannot decode image: $imagePath")
        val enhancedBitmap = enhance(inputBitmap, mode)
        val outputFile = File(context.filesDir, "enhanced_${System.currentTimeMillis()}.jpg")
        enhancedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, FileOutputStream(outputFile))
        inputBitmap.recycle()
        enhancedBitmap.recycle()
        return outputFile.absolutePath
    }

    private fun applyMagicColor(mat: Mat): Bitmap {
        val bgr = Mat()
        Imgproc.cvtColor(mat, bgr, Imgproc.COLOR_RGBA2BGR)
        val lab = Mat()
        Imgproc.cvtColor(bgr, lab, Imgproc.COLOR_BGR2Lab)
        val channels = ArrayList<Mat>()
        Core.split(lab, channels)
        val clahe = Imgproc.createCLAHE(3.0, Size(8.0, 8.0))
        clahe.apply(channels[0], channels[0])
        Core.merge(channels, lab)
        channels.forEach { it.release() }
        val resultBgr = Mat()
        Imgproc.cvtColor(lab, resultBgr, Imgproc.COLOR_Lab2BGR)
        val hsv = Mat()
        Imgproc.cvtColor(resultBgr, hsv, Imgproc.COLOR_BGR2HSV_FULL)
        val hsvChannels = ArrayList<Mat>()
        Core.split(hsv, hsvChannels)
        Core.multiply(hsvChannels[1], Scalar(1.2), hsvChannels[1])
        Core.min(hsvChannels[1], Scalar(255.0), hsvChannels[1])
        Core.merge(hsvChannels, hsv)
        hsvChannels.forEach { it.release() }
        Imgproc.cvtColor(hsv, resultBgr, Imgproc.COLOR_HSV2BGR_FULL)
        val result = Mat()
        Imgproc.cvtColor(resultBgr, result, Imgproc.COLOR_BGR2RGBA)
        val output = Bitmap.createBitmap(result.cols(), result.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(result, output)
        mat.release(); bgr.release(); lab.release(); resultBgr.release(); hsv.release()
        return output
    }

    private fun applyGrayscale(mat: Mat): Bitmap {
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)
        val result = Mat()
        Imgproc.cvtColor(gray, result, Imgproc.COLOR_GRAY2RGBA)
        val output = Bitmap.createBitmap(result.cols(), result.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(result, output)
        mat.release(); gray.release(); result.release()
        return output
    }

    private fun applyBlackWhite(mat: Mat): Bitmap {
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)
        val result = Mat()
        Imgproc.adaptiveThreshold(gray, result, 255.0, Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C, Imgproc.THRESH_BINARY, 11, 2.0)
        val rgba = Mat()
        Imgproc.cvtColor(result, rgba, Imgproc.COLOR_GRAY2RGBA)
        val output = Bitmap.createBitmap(rgba.cols(), rgba.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(rgba, output)
        mat.release(); gray.release(); result.release(); rgba.release()
        return output
    }

    private fun applyWhiteboard(mat: Mat): Bitmap {
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)
        val blurred = Mat()
        Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)
        val normalized = Mat()
        Core.normalize(blurred, normalized, 0.0, 255.0, Core.NORM_MINMAX)
        val result = Mat()
        Imgproc.threshold(normalized, result, 180.0, 255.0, Imgproc.THRESH_TRUNC)
        Core.add(result, Scalar(30.0), result)
        val rgba = Mat()
        Imgproc.cvtColor(result, rgba, Imgproc.COLOR_GRAY2RGBA)
        val output = Bitmap.createBitmap(rgba.cols(), rgba.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(rgba, output)
        mat.release(); gray.release(); blurred.release(); normalized.release(); result.release(); rgba.release()
        return output
    }

    fun buildPdfNative(imagePaths: List<String>, title: String): String {
        if (imagePaths.isEmpty()) throw IllegalArgumentException("No images provided for PDF generation")
        val pdfFile = File(context.filesDir, "${sanitizeTitle(title)}_${System.currentTimeMillis()}.pdf")
        val pdfDocument = PdfDocument()
        try {
            for ((index, imagePath) in imagePaths.withIndex()) {
                val bitmap = BitmapFactory.decodeFile(imagePath)
                    ?: throw IllegalArgumentException("Cannot decode image: $imagePath")
                val scaledBitmap = scaleBitmapToA4(bitmap)
                val pageInfo = PdfDocument.PageInfo.Builder(scaledBitmap.width, scaledBitmap.height, index + 1).create()
                val page = pdfDocument.startPage(pageInfo)
                page.canvas.drawBitmap(scaledBitmap, 0f, 0f, null)
                pdfDocument.finishPage(page)
                bitmap.recycle(); scaledBitmap.recycle()
            }
            FileOutputStream(pdfFile).use { pdfDocument.writeTo(it) }
            return pdfFile.absolutePath
        } finally {
            pdfDocument.close()
        }
    }

    fun extractText(imagePath: String, onResult: (String) -> Unit) {
        val file = File(imagePath)
        if (!file.exists()) { onResult(""); return }
        val image = InputImage.fromFilePath(context, Uri.fromFile(file))
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { visionText -> onResult(visionText.text); recognizer.close() }
            .addOnFailureListener { e -> Log.e(TAG, "OCR failed", e); onResult(""); recognizer.close() }
    }

    private fun ImageProxy.toBitmap(): Bitmap {
        val plane = planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        if (rowStride == width * pixelStride) {
            bitmap.copyPixelsFromBuffer(buffer)
        } else {
            val bitmapBuffer = ByteBuffer.allocate(width * height * 4)
            val rowBytes = ByteArray(width * 4)
            buffer.rewind()
            for (row in 0 until height) {
                buffer.position(row * rowStride)
                buffer.get(rowBytes, 0, width * 4)
                bitmapBuffer.put(rowBytes)
            }
            bitmapBuffer.rewind()
            bitmap.copyPixelsFromBuffer(bitmapBuffer)
        }
        val rotationDegrees = imageInfo.rotationDegrees
        if (rotationDegrees != 0) {
            val matrix = Matrix().apply { postRotate(rotationDegrees.toFloat()) }
            val rotatedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            bitmap.recycle()
            return rotatedBitmap
        }
        return bitmap
    }

    private fun applyTemporalSmoothing(rawCorners: List<Double>): List<Double> {
        val prev = smoothedCorners
        if (prev == null || prev.size != rawCorners.size) {
            smoothedCorners = rawCorners
            return rawCorners
        }
        var maxDelta = 0.0
        for (i in rawCorners.indices) {
            val d = kotlin.math.abs(rawCorners[i] - prev[i])
            if (d > maxDelta) maxDelta = d
        }
        return if (maxDelta > snapDistanceThreshold) {
            smoothedCorners = rawCorners
            rawCorners
        } else {
            val blended = rawCorners.indices.map { i -> prev[i] + emaAlpha * (rawCorners[i] - prev[i]) }
            smoothedCorners = blended
            blended
        }
    }

    private fun flattenCorners(corners: MatOfPoint2f): List<Double> =
        corners.toArray().flatMap { listOf(it.x, it.y) }

    private fun deflattenCorners(flat: List<Double>): MatOfPoint2f =
        MatOfPoint2f(*flat.chunked(2).map { (x, y) -> Point(x, y) }.toTypedArray())

    private fun distance(p1: Point, p2: Point): Double =
        Math.sqrt(Math.pow(p2.x - p1.x, 2.0) + Math.pow(p2.y - p1.y, 2.0))

    private fun limitSize(width: Int, height: Int): Pair<Int, Int> {
        val maxDim = maxOf(width, height)
        if (maxDim <= MAX_OUTPUT_SIZE) return Pair(width, height)
        val scale = MAX_OUTPUT_SIZE.toDouble() / maxDim
        return Pair((width * scale).toInt(), (height * scale).toInt())
    }

    private fun scaleBitmapToA4(bitmap: Bitmap): Bitmap {
        val aspectRatio = bitmap.width.toDouble() / bitmap.height.toDouble()
        val a4AspectRatio = 210.0 / 297.0
        val targetWidth: Int
        val targetHeight: Int
        if (aspectRatio > a4AspectRatio) {
            targetWidth = 2480
            targetHeight = (targetWidth / aspectRatio).toInt()
        } else {
            targetHeight = 3508
            targetWidth = (targetHeight * aspectRatio).toInt()
        }
        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }

    private fun sanitizeTitle(title: String): String =
        title.replace(Regex("[^\\w\\s-]"), "").trim().replace(" ", "_")

    fun getFrameDimensions(): Pair<Int, Int> = Pair(lastAnalyzedFrameWidth, lastAnalyzedFrameHeight)
}
