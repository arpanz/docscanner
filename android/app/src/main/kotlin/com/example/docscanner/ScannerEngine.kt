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
import androidx.exifinterface.media.ExifInterface
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
    private val emaAlpha = 0.16
    private val snapDistanceThreshold = 180.0
    private val maxNoDetectionFrames = 12

    // Callbacks
    var onFrameAnalyzed: ((Bitmap, List<Double>, Int, Int) -> Unit)? = null
    var onEdgeDetected: ((List<Double>, Int, Int, Boolean, Double) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    private data class DetectedDocument(
        val corners: List<Double>,
        val confidence: Double
    )

    private data class CandidateShape(
        val quad: Array<Point>,
        val contourArea: Double
    )

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
                                    val detection = detectDocument(bitmap)
                                    val frameWidth = bitmap.width
                                    val frameHeight = bitmap.height
                                    lastAnalyzedFrameWidth = frameWidth
                                    lastAnalyzedFrameHeight = frameHeight

                                    if (detection != null) {
                                        noDetectionCount = 0
                                        val emitted = applyTemporalSmoothing(detection.corners)
                                        onEdgeDetected?.invoke(
                                            emitted,
                                            frameWidth,
                                            frameHeight,
                                            true,
                                            detection.confidence
                                        )
                                        onFrameAnalyzed?.invoke(bitmap, emitted, frameWidth, frameHeight)
                                    } else {
                                        noDetectionCount++
                                        if (noDetectionCount >= maxNoDetectionFrames) {
                                            smoothedCorners = null
                                        }
                                        smoothedCorners?.let { prev ->
                                            onEdgeDetected?.invoke(prev, frameWidth, frameHeight, false, 0.0)
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
     * Apply perspective correction to an already-captured raw image.
     *
     * Unlike the old approach that took a second photo, this works on the raw
     * file from [captureRaw], so the crop always matches what the user saw.
     *
     * @param rawImagePath Path to the raw captured image
     * @param corners The 4 corner points in the raw image's coordinate space
     *                (already scaled to actual image dimensions by Flutter)
     * @param onCaptureComplete Callback with the saved cropped file path
     */
    fun captureDocumentFromRaw(rawImagePath: String, corners: List<Double>, onCaptureComplete: (String) -> Unit) {
        if (corners.size < 8) {
            onError?.invoke("Invalid corners data")
            return
        }

        try {
            // Decode and apply EXIF rotation to get the correctly oriented bitmap
            val bitmap = decodeWithExifRotation(rawImagePath)
                ?: throw IllegalArgumentException("Cannot decode image: $rawImagePath")

            val cornerPoints = deflattenCorners(corners)
            val correctedBitmap = perspectiveCorrect(bitmap, cornerPoints)

            val outputFile = File(context.filesDir, "scan_${System.currentTimeMillis()}.jpg")
            FileOutputStream(outputFile).use {
                correctedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)
            }
            correctedBitmap.recycle()
            bitmap.recycle()
            onCaptureComplete(outputFile.absolutePath)
        } catch (e: Exception) {
            Log.e(TAG, "Perspective correction failed", e)
            onError?.invoke("Failed to process image: ${e.message}")
        }
    }

    fun cropImage(imagePath: String, corners: List<Double>): String {
        if (corners.size < 8) throw IllegalArgumentException("Invalid corners data")

        // Decode with EXIF rotation so corners match the displayed orientation
        val inputBitmap = decodeWithExifRotation(imagePath)
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

    private fun detectDocument(bitmap: Bitmap): DetectedDocument? {
        if (!ensureOpenCvReady()) return null

        var mat: Mat? = null
        var gray: Mat? = null
        var blurred: Mat? = null
        var edgeMask: Mat? = null
        var adaptiveMask: Mat? = null
        var dilatedEdges: Mat? = null

        try {
            mat = Mat()
            Utils.bitmapToMat(bitmap, mat)

            gray = Mat()
            blurred = Mat()

            Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)
            // Use smaller 3×3 kernel to preserve edge details
            Imgproc.GaussianBlur(gray, blurred, Size(3.0, 3.0), 0.0)

            // Apply mild dilation before edge detection to strengthen faint document edges
            val dilateKernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
            dilatedEdges = Mat()
            Imgproc.dilate(blurred, dilatedEdges, dilateKernel)
            dilateKernel.release()

            edgeMask = buildEdgeMask(dilatedEdges)
            adaptiveMask = buildAdaptiveMask(dilatedEdges)

            val frameWidth = mat.width()
            val frameHeight = mat.height()
            val frameArea = frameWidth * frameHeight.toDouble()
            // Lower minimum area to catch smaller documents
            val minArea = frameArea * 0.04

            val candidates = mutableListOf<DetectedDocument>()
            candidates += collectCandidates(edgeMask, minArea, frameWidth, frameHeight, frameArea)
            candidates += collectCandidates(adaptiveMask, minArea, frameWidth, frameHeight, frameArea)

            // Lower confidence threshold for suboptimal conditions
            return candidates
                .filter { it.confidence >= 0.22 }
                .maxByOrNull { it.confidence }
        } catch (t: Throwable) {
            Log.e(TAG, "Edge detection failed", t)
            return null
        } finally {
            mat?.release()
            gray?.release()
            blurred?.release()
            edgeMask?.release()
            adaptiveMask?.release()
            dilatedEdges?.release()
        }
    }

    private fun buildEdgeMask(blurred: Mat): Mat {
        val edges = Mat()
        val lowerThreshold = computeAdaptiveCannyThreshold(blurred)
        // Reduce ratio from 2.4 to 2.0 for better edge connectivity
        val upperThreshold = lowerThreshold * 2.0
        Imgproc.Canny(blurred, edges, lowerThreshold, upperThreshold)

        // Keep gaps closed without inflating the detected page boundary.
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        val closed = Mat()
        Imgproc.morphologyEx(edges, closed, Imgproc.MORPH_CLOSE, kernel)
        kernel.release()
        edges.release()
        return closed
    }

    private fun buildAdaptiveMask(blurred: Mat): Mat {
        val adaptive = Mat()
        // Use larger block size and lower C for better performance in varying lighting
        Imgproc.adaptiveThreshold(
            blurred,
            adaptive,
            255.0,
            Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
            Imgproc.THRESH_BINARY,
            51,
            5.0
        )
        Core.bitwise_not(adaptive, adaptive)
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        Imgproc.morphologyEx(adaptive, adaptive, Imgproc.MORPH_CLOSE, kernel)
        kernel.release()
        return adaptive
    }

    private fun collectCandidates(
        mask: Mat,
        minArea: Double,
        frameWidth: Int,
        frameHeight: Int,
        frameArea: Double
    ): List<DetectedDocument> {
        val contours = ArrayList<MatOfPoint>()
        val hierarchy = Mat()
        try {
            Imgproc.findContours(
                mask,
                contours,
                hierarchy,
                Imgproc.RETR_EXTERNAL,
                Imgproc.CHAIN_APPROX_SIMPLE
            )
            return contours
                .sortedByDescending { kotlin.math.abs(Imgproc.contourArea(it)) }
                .take(12)
                .mapNotNull { contour ->
                buildCandidateFromContour(contour, minArea, frameWidth, frameHeight, frameArea)
                }
        } finally {
            hierarchy.release()
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
        // More sensitive threshold calculation for better edge detection
        val contrastFactor = stdDev / 40.0
        return (80.0 * contrastFactor).coerceIn(35.0, 120.0)
    }

    private fun buildCandidateFromContour(
        contour: MatOfPoint,
        minArea: Double,
        frameWidth: Int,
        frameHeight: Int,
        frameArea: Double
    ): DetectedDocument? {
        val candidate = buildCandidateShape(contour, minArea) ?: return null
        if (!isValidQuadrilateral(candidate.quad, frameWidth, frameHeight, frameArea)) {
            return null
        }

        return DetectedDocument(
            corners = flattenCornerPoints(candidate.quad),
            confidence = scoreQuad(
                candidate.quad,
                candidate.contourArea,
                frameWidth,
                frameHeight,
                frameArea
            )
        )
    }

    private fun buildCandidateShape(contour: MatOfPoint, minArea: Double): CandidateShape? {
        val contourArea = kotlin.math.abs(Imgproc.contourArea(contour))
        if (contourArea < minArea) return null

        val hull = convexHullContour(contour)
        try {
            val hullArea = kotlin.math.abs(Imgproc.contourArea(hull))
            if (hullArea < minArea) return null

            val quad =
                approxQuad(hull) ?: minAreaRectQuad(hull, hullArea)
                ?: return null

            val quadArea = polygonArea(quad)
            if (quadArea <= 0.0) return null

            val fillRatio = (hullArea / quadArea).coerceIn(0.0, 1.4)
            // Lower fill ratio threshold to accept slightly irregular documents
            if (fillRatio < 0.58) return null

            return CandidateShape(quad = quad, contourArea = hullArea)
        } finally {
            hull.release()
        }
    }

    private fun approxQuad(contour: MatOfPoint): Array<Point>? {
        val contour2f = MatOfPoint2f(*contour.toArray())
        try {
            val perimeter = Imgproc.arcLength(contour2f, true)
            // Use finer epsilon values for more precise corner detection
            val epsilons = doubleArrayOf(0.010, 0.015, 0.020, 0.028)
            for (epsilon in epsilons) {
                val approx = MatOfPoint2f()
                try {
                    Imgproc.approxPolyDP(contour2f, approx, epsilon * perimeter, true)
                    if (approx.total() == 4L) {
                        return orderPoints(approx.toArray())
                    }
                } finally {
                    approx.release()
                }
            }
            return null
        } finally {
            contour2f.release()
        }
    }

    private fun minAreaRectQuad(contour: MatOfPoint, contourArea: Double): Array<Point>? {
        val contour2f = MatOfPoint2f(*contour.toArray())
        try {
            val rect = Imgproc.minAreaRect(contour2f)
            val rectArea = rect.size.width * rect.size.height
            if (rectArea <= 0.0) return null
            // Lower fill ratio threshold to match buildCandidateShape
            if ((contourArea / rectArea) < 0.58) return null

            val points = Array(4) { Point() }
            rect.points(points)
            return orderPoints(points)
        } finally {
            contour2f.release()
        }
    }

    private fun convexHullContour(contour: MatOfPoint): MatOfPoint {
        val hullIndices = MatOfInt()
        try {
            Imgproc.convexHull(contour, hullIndices)
            val contourPoints = contour.toArray()
            val hullPoints = hullIndices.toArray().map { contourPoints[it] }.toTypedArray()
            return MatOfPoint(*hullPoints)
        } finally {
            hullIndices.release()
        }
    }

    private fun scoreQuad(
        points: Array<Point>,
        contourArea: Double,
        frameWidth: Int,
        frameHeight: Int,
        frameArea: Double
    ): Double {
        val quadArea = polygonArea(points)
        val areaRatio = quadArea / frameArea
        val sizeScore = (1.0 - kotlin.math.abs(areaRatio - 0.46) / 0.46).coerceIn(0.0, 1.0)
        val center = Point(
            points.map { it.x }.average(),
            points.map { it.y }.average()
        )
        val frameCenter = Point(frameWidth / 2.0, frameHeight / 2.0)
        val maxDistance = kotlin.math.hypot(frameWidth.toDouble(), frameHeight.toDouble()) / 2.0
        val centerScore = (1.0 - distance(center, frameCenter) / maxDistance).coerceIn(0.0, 1.0)
        val widthTop = distance(points[0], points[1])
        val widthBottom = distance(points[3], points[2])
        val heightLeft = distance(points[0], points[3])
        val heightRight = distance(points[1], points[2])
        val avgWidth = (widthTop + widthBottom) / 2.0
        val avgHeight = (heightLeft + heightRight) / 2.0
        val aspectRatio = if (avgHeight == 0.0) 0.0 else avgWidth / avgHeight
        val aspectScore = when {
            aspectRatio in 0.35..2.6 -> 1.0
            aspectRatio in 0.25..4.0 -> 0.72
            else -> 0.0
        }
        val angleScore = averageAngleScore(points)
        val continuityScore = continuityScore(points, frameWidth, frameHeight)
        val fillScore = (contourArea / quadArea).coerceIn(0.0, 1.0)
        val borderScore = borderClearanceScore(points, frameWidth, frameHeight)

        return (
            (sizeScore * 0.25) +
                (centerScore * 0.14) +
                (aspectScore * 0.10) +
                (angleScore * 0.18) +
                (fillScore * 0.18) +
                (borderScore * 0.08) +
                (continuityScore * 0.07)
            ).coerceIn(0.0, 1.0)
    }

    private fun continuityScore(points: Array<Point>, frameWidth: Int, frameHeight: Int): Double {
        val previous = smoothedCorners ?: return 0.62
        if (previous.size != 8) return 0.62

        val previousPoints = previous.chunked(2).map { Point(it[0], it[1]) }
        val frameDiagonal = kotlin.math.hypot(frameWidth.toDouble(), frameHeight.toDouble())
        val averageDistance =
            points.indices.map { index -> distance(points[index], previousPoints[index]) }.average()
        return (1.0 - (averageDistance / (frameDiagonal * 0.18))).coerceIn(0.0, 1.0)
    }

    private fun averageAngleScore(points: Array<Point>): Double {
        return points.indices.map { index ->
            val prev = points[(index + 3) % 4]
            val current = points[index]
            val next = points[(index + 1) % 4]
            val angle = interiorAngle(prev, current, next)
            (1.0 - (kotlin.math.abs(angle - 90.0) / 65.0)).coerceIn(0.0, 1.0)
        }.average()
    }

    private fun borderClearanceScore(points: Array<Point>, frameWidth: Int, frameHeight: Int): Double {
        val minDistanceToBorder = points.minOf { point ->
            minOf(
                point.x,
                point.y,
                frameWidth - point.x,
                frameHeight - point.y
            )
        }
        val target = minOf(frameWidth, frameHeight) * 0.04
        return (minDistanceToBorder / target).coerceIn(0.0, 1.0)
    }

    private fun interiorAngle(prev: Point, current: Point, next: Point): Double {
        val ax = prev.x - current.x
        val ay = prev.y - current.y
        val bx = next.x - current.x
        val by = next.y - current.y
        val magA = kotlin.math.hypot(ax, ay)
        val magB = kotlin.math.hypot(bx, by)
        if (magA == 0.0 || magB == 0.0) return 0.0
        val cosTheta = ((ax * bx) + (ay * by)) / (magA * magB)
        return Math.toDegrees(kotlin.math.acos(cosTheta.coerceIn(-1.0, 1.0)))
    }

    private fun isValidQuadrilateral(
        points: Array<Point>,
        frameWidth: Int,
        frameHeight: Int,
        frameArea: Double
    ): Boolean {
        if (points.size != 4) return false
        // Lower area ratio threshold to detect smaller documents
        val areaRatio = polygonArea(points) / frameArea
        if (areaRatio < 0.03 || areaRatio > 0.96) return false

        // Reduce minimum side length requirement
        val minSideLength = minOf(frameWidth, frameHeight) * 0.08
        val sides = listOf(
            distance(points[0], points[1]),
            distance(points[1], points[2]),
            distance(points[2], points[3]),
            distance(points[3], points[0])
        )
        if (sides.any { it < minSideLength }) return false

        val widthTop = distance(points[0], points[1])
        val widthBottom = distance(points[3], points[2])
        val heightLeft = distance(points[0], points[3])
        val heightRight = distance(points[1], points[2])
        val avgWidth = (widthTop + widthBottom) / 2.0
        val avgHeight = (heightLeft + heightRight) / 2.0
        if (avgWidth == 0.0 || avgHeight == 0.0) return false

        val aspectRatio = avgWidth / avgHeight
        if (aspectRatio > 4.2 || aspectRatio < 0.22) return false

        val fillRatio = contourFillRatio(points)
        // Lower fill ratio and angle score thresholds for better detection
        if (fillRatio < 0.45) return false
        if (averageAngleScore(points) < 0.25) return false
        return true
    }

    private fun contourFillRatio(points: Array<Point>): Double {
        val rect = Imgproc.boundingRect(MatOfPoint(*points))
        val rectArea = rect.width * rect.height.toDouble()
        if (rectArea <= 0.0) return 0.0
        return (polygonArea(points) / rectArea).coerceIn(0.0, 1.0)
    }

    private fun orderPoints(points: Array<Point>): Array<Point> {
        val topLeft = points.minByOrNull { it.x + it.y } ?: return points
        val bottomRight = points.maxByOrNull { it.x + it.y } ?: return points
        val topRight = points.minByOrNull { it.y - it.x } ?: return points
        val bottomLeft = points.maxByOrNull { it.y - it.x } ?: return points
        return arrayOf(topLeft, topRight, bottomRight, bottomLeft)
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
            val adaptiveAlpha = when {
                maxDelta > 90.0 -> 0.28
                maxDelta > 45.0 -> 0.22
                else -> emaAlpha
            }
            val blended = rawCorners.indices.map { i ->
                prev[i] + adaptiveAlpha * (rawCorners[i] - prev[i])
            }
            smoothedCorners = blended
            blended
        }
    }

    private fun flattenCornerPoints(corners: Array<Point>): List<Double> =
        corners.flatMap { listOf(it.x, it.y) }

    private fun deflattenCorners(flat: List<Double>): MatOfPoint2f =
        MatOfPoint2f(*flat.chunked(2).map { (x, y) -> Point(x, y) }.toTypedArray())

    private fun distance(p1: Point, p2: Point): Double =
        Math.sqrt(Math.pow(p2.x - p1.x, 2.0) + Math.pow(p2.y - p1.y, 2.0))

    private fun polygonArea(points: Array<Point>): Double {
        var area = 0.0
        for (i in points.indices) {
            val next = points[(i + 1) % points.size]
            area += (points[i].x * next.y) - (next.x * points[i].y)
        }
        return kotlin.math.abs(area) / 2.0
    }

    private fun limitSize(width: Int, height: Int): Pair<Int, Int> {
        val maxDim = maxOf(width, height)
        if (maxDim <= MAX_OUTPUT_SIZE) return Pair(width, height)
        val scale = MAX_OUTPUT_SIZE.toDouble() / maxDim
        return Pair((width * scale).toInt(), (height * scale).toInt())
    }

    /**
     * Decode an image file and apply EXIF rotation so the returned Bitmap
     * matches the visual orientation the user sees on screen.
     */
    private fun decodeWithExifRotation(imagePath: String): Bitmap? {
        val bitmap = BitmapFactory.decodeFile(imagePath) ?: return null
        val exif = ExifInterface(imagePath)
        val orientation = exif.getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL
        )
        val rotationDegrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (rotationDegrees == 0f) return bitmap
        val matrix = Matrix().apply { postRotate(rotationDegrees) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        bitmap.recycle()
        return rotated
    }

    /**
     * Get the actual display dimensions of an image file, accounting for EXIF rotation.
     * Returns (width, height) as they would appear when displayed correctly.
     */
    fun getImageDimensions(imagePath: String): Pair<Int, Int> {
        // Use BitmapFactory.Options to read dimensions without loading full bitmap
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(imagePath, options)
        val rawWidth = options.outWidth
        val rawHeight = options.outHeight
        if (rawWidth <= 0 || rawHeight <= 0) return Pair(0, 0)

        val exif = ExifInterface(imagePath)
        val orientation = exif.getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL
        )
        // For 90° and 270° rotations, width and height are swapped
        return when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90,
            ExifInterface.ORIENTATION_ROTATE_270 -> Pair(rawHeight, rawWidth)
            else -> Pair(rawWidth, rawHeight)
        }
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
