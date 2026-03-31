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

    // Track current frame dimensions for overlay scaling
    // NOTE: These are now deprecated - frame dimensions are passed with each detection result
    @Deprecated("Use frame dimensions from detection result instead")
    private var currentFrameWidth: Int = 0
    @Deprecated("Use frame dimensions from detection result instead")
    private var currentFrameHeight: Int = 0

    // Store the last analyzed frame dimensions atomically with corner data
    private var lastAnalyzedFrameWidth: Int = 0
    private var lastAnalyzedFrameHeight: Int = 0

    // Callbacks
    var onFrameAnalyzed: ((Bitmap, List<Double>, Int, Int) -> Unit)? = null
    var onEdgeDetected: ((List<Double>, Int, Int) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    /**
     * Initialize OpenCV native bindings once for this engine instance.
     */
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

    /**
     * Prevent repeated error spam if OpenCV isn't available on this build/device.
     */
    private fun ensureOpenCvReady(): Boolean {
        if (openCvInitialized) {
            return true
        }

        if (!openCvErrorReported) {
            openCvErrorReported = true
            val message = "OpenCV native library is unavailable. Rebuild and reinstall the app."
            Log.e(TAG, message)
            onError?.invoke(message)
        }
        return false
    }

    /**
     * Start CameraX preview with frame analysis for edge detection.
     *
     * @param previewView The PreviewView to display camera feed
     * @param enableFrameAnalysis Whether to run edge detection on each frame
     */
    fun startCamera(
        previewView: PreviewView,
        enableFrameAnalysis: Boolean = true
    ) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()

                // Preview use case - displays camera feed
                preview = Preview.Builder()
                    .build()
                    .also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }

                // ImageAnalysis use case - for edge detection on each frame
                if (enableFrameAnalysis && ensureOpenCvReady()) {
                    imageAnalyzer = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                        .build()
                        .also { analysis ->
                            analysis.setAnalyzer(cameraExecutor) { imageProxy ->
                                try {
                                    val bitmap = imageProxy.toBitmap()
                                    val corners = detectDocumentContour(bitmap)

                                    // Store frame dimensions atomically with this frame's detection
                                    val frameWidth = bitmap.width
                                    val frameHeight = bitmap.height
                                    lastAnalyzedFrameWidth = frameWidth
                                    lastAnalyzedFrameHeight = frameHeight

                                    // Send corners + frame dimensions to Flutter for overlay drawing
                                    corners?.let {
                                        val cornerList = flattenCorners(it)
                                        onEdgeDetected?.invoke(cornerList, frameWidth, frameHeight)
                                        onFrameAnalyzed?.invoke(bitmap, cornerList, frameWidth, frameHeight)
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

                // ImageCapture use case - for high-res captures
                imageCapture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                    .setTargetResolution(android.util.Size(MAX_OUTPUT_SIZE, MAX_OUTPUT_SIZE))
                    .build()

                // Unbind all use cases before rebinding
                cameraProvider.unbindAll()

                // Bind use cases to camera
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

    /**
     * Stop camera and release resources.
     */
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

    /**
     * Set flash torch on or off.
     */
    fun setFlashTorch(enabled: Boolean) {
        camera?.let {
            if (it.cameraInfo.hasFlashUnit()) {
                it.cameraControl.enableTorch(enabled)
            }
        }
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

        // Create output file
        val outputDir = context.filesDir
        val outputFile = File(outputDir, "scan_${System.currentTimeMillis()}.jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()

        // Capture the image
        imageCapture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    // Apply perspective correction
                    val capturedBitmap = BitmapFactory.decodeFile(outputFile.absolutePath)
                        ?: run {
                            onError?.invoke("Failed to decode captured image")
                            return
                        }

                    try {
                        // Scale corners from analysis frame coordinates to capture image coordinates
                        // Use the frame dimensions stored with the corner detection to avoid race conditions
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

    /**
     * Crop an existing image using perspective correction and save the result.
     */
    fun cropImage(imagePath: String, corners: List<Double>): String {
        if (corners.size < 8) {
            throw IllegalArgumentException("Invalid corners data")
        }

        val inputBitmap = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalArgumentException("Cannot decode image: $imagePath")

        val croppedBitmap = try {
            perspectiveCorrect(inputBitmap, deflattenCorners(corners))
        } finally {
            inputBitmap.recycle()
        }

        val outputDir = context.filesDir
        val outputFile = File(outputDir, "cropped_${System.currentTimeMillis()}.jpg")

        try {
            FileOutputStream(outputFile).use { outputStream ->
                croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
            }
            return outputFile.absolutePath
        } finally {
            croppedBitmap.recycle()
        }
    }

    /**
     * Detect document contour in a bitmap using OpenCV.
     * Returns 4 corner points if a document is found, null otherwise.
     * 
     * Uses adaptive thresholding and RETR_EXTERNAL for stable edge detection.
     */
    fun detectDocumentContour(bitmap: Bitmap): MatOfPoint2f? {
        if (!ensureOpenCvReady()) {
            return null
        }

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

            // Convert to grayscale
            Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)

            // Moderate Gaussian blur to reduce noise without losing document edges
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)

            // Adaptive Canny edge detection with automatic thresholds
            val lowerThreshold = computeAdaptiveCannyThreshold(blurred)
            val upperThreshold = lowerThreshold * 2.5
            Imgproc.Canny(blurred, edges, lowerThreshold, upperThreshold)

            // Light morphological closing to connect broken edges (helps with textured backgrounds)
            val kernel = Imgproc.getStructuringElement(
                Imgproc.MORPH_RECT,
                Size(3.0, 3.0)
            )
            val closedEdges = Mat()
            Imgproc.morphologyEx(edges, closedEdges, Imgproc.MORPH_CLOSE, kernel)
            kernel.release()

            // Find ONLY external contours - avoids picking up internal texture
            Imgproc.findContours(
                closedEdges,
                contours,
                null,
                Imgproc.RETR_EXTERNAL,
                Imgproc.CHAIN_APPROX_SIMPLE
            )

            closedEdges.release()

            // Find the largest 4-sided contour (the document)
            // Reasonable minimum area - at least 3% of image to ignore small noise
            val minArea = (blurred.width() * blurred.height()) * 0.03
            return contours
                .filter { Imgproc.contourArea(it) > minArea }
                .sortedByDescending { Imgproc.contourArea(it) }
                .firstNotNullOfOrNull { contour ->
                    approxQuad(contour)
                }
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

    /**
     * Compute adaptive Canny threshold using image statistics.
     * This makes edge detection adapt to different lighting conditions.
     */
    private fun computeAdaptiveCannyThreshold(gray: Mat): Double {
        // Calculate mean and standard deviation of pixel intensities
        val meanMat = MatOfDouble()
        val stdDevMat = MatOfDouble()
        Core.meanStdDev(gray, meanMat, stdDevMat)
        
        val mean = meanMat.toArray()[0]
        val stdDev = stdDevMat.toArray()[0]
        
        meanMat.release()
        stdDevMat.release()

        // Adaptive threshold based on image contrast
        // Low contrast scenes need lower thresholds
        // High contrast scenes can use higher thresholds
        val baseThreshold = 100.0
        val contrastFactor = stdDev / 50.0  // Normalize around typical document contrast

        // Clamp between 50 and 150 for stability
        return (baseThreshold * (1.0 / (contrastFactor + 0.5))).coerceIn(50.0, 150.0)
    }

    /**
     * Approximate a contour to a quadrilateral.
     * Returns null if the contour doesn't form a valid quad.
     */
    private fun approxQuad(contour: MatOfPoint): MatOfPoint2f? {
        // Convert MatOfPoint to MatOfPoint2f for arcLength
        val contour2f = MatOfPoint2f(*contour.toArray().map { p ->
            Point(p.x.toDouble(), p.y.toDouble())
        }.toTypedArray())

        val peri = Imgproc.arcLength(contour2f, true)
        val approx = MatOfPoint2f()
        // Slightly tighter epsilon for more accurate corner detection (0.015 instead of 0.02)
        Imgproc.approxPolyDP(contour2f, approx, 0.015 * peri, true)
        contour2f.release()

        if (approx.total() != 4L) {
            approx.release()
            return null
        }

        val ordered = orderPoints(approx)
        
        // Validate the quadrilateral - reject self-intersecting or extreme quads
        if (!isValidQuadrilateral(ordered)) {
            ordered.release()
            return null
        }
        
        return ordered
    }

    /**
     * Validate that 4 points form a proper convex quadrilateral.
     * Rejects self-intersecting quads and extreme aspect ratios.
     */
    private fun isValidQuadrilateral(points: MatOfPoint2f): Boolean {
        val pts = points.toArray()
        if (pts.size < 4) return false

        // Check for convexity using cross product
        // All cross products should have the same sign for a convex quad
        val crossProducts = mutableListOf<Double>()
        for (i in 0..3) {
            val p1 = pts[i]
            val p2 = pts[(i + 1) % 4]
            val p3 = pts[(i + 2) % 4]
            
            // Vector p1->p2
            val v1x = p2.x - p1.x
            val v1y = p2.y - p1.y
            // Vector p2->p3
            val v2x = p3.x - p2.x
            val v2y = p3.y - p2.y
            
            // Cross product (z-component)
            val cross = v1x * v2y - v1y * v2x
            crossProducts.add(cross)
        }

        // All cross products must have the same sign (all positive or all negative)
        val allPositive = crossProducts.all { it > 0 }
        val allNegative = crossProducts.all { it < 0 }
        if (!allPositive && !allNegative) return false

        // Check aspect ratio - reject extremely skewed quads
        val widthTop = distance(pts[0], pts[1])
        val widthBottom = distance(pts[3], pts[2])
        val heightLeft = distance(pts[0], pts[3])
        val heightRight = distance(pts[1], pts[2])
        
        val avgWidth = (widthTop + widthBottom) / 2
        val avgHeight = (heightLeft + heightRight) / 2
        
        // Reject quads with extreme aspect ratios (> 10:1 or < 1:10)
        if (avgWidth > 0 && avgHeight > 0) {
            val aspectRatio = avgWidth / avgHeight
            if (aspectRatio > 10.0 || aspectRatio < 0.1) return false
        }

        // Check minimum area (at least 1000 pixels to avoid noise)
        val area = Imgproc.contourArea(points)
        if (area < 1000) return false

        return true
    }

    /**
     * Order points in clockwise order: top-left, top-right, bottom-right, bottom-left.
     */
    private fun orderPoints(points: MatOfPoint2f): MatOfPoint2f {
        val pts = points.toArray()
        val sorted = pts.sortedWith(compareBy({ it.y }, { it.x }))

        // Top two points (smallest y)
        val topTwo = sorted.take(2).sortedBy { it.x }
        // Bottom two points (largest y)
        val bottomTwo = sorted.takeLast(2).sortedBy { it.x }

        val ordered = arrayOf(
            topTwo[0],  // top-left
            topTwo[1],  // top-right
            bottomTwo[1], // bottom-right
            bottomTwo[0]  // bottom-left
        )

        return MatOfPoint2f(*ordered)
    }

    /**
     * Apply perspective correction to extract and flatten the document.
     */
    fun perspectiveCorrect(bitmap: Bitmap, corners: MatOfPoint2f): Bitmap {
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)

        val result = Mat()
        var dstPoints = MatOfPoint2f()
        var transform = Mat()

        try {
            // Get ordered corner points
            val srcPoints = corners.toArray()

            // Calculate output dimensions based on aspect ratio
            val widthTop = distance(srcPoints[0], srcPoints[1])
            val widthBottom = distance(srcPoints[3], srcPoints[2])
            val maxWidth = maxOf(widthTop, widthBottom).toInt()

            val heightLeft = distance(srcPoints[0], srcPoints[3])
            val heightRight = distance(srcPoints[1], srcPoints[2])
            val maxHeight = maxOf(heightLeft, heightRight).toInt()

            // Limit output size
            val (outputWidth, outputHeight) = limitSize(maxWidth, maxHeight)

            // Destination points (rectangle)
            dstPoints.release()
            dstPoints = MatOfPoint2f(
                Point(0.0, 0.0),
                Point(outputWidth.toDouble(), 0.0),
                Point(outputWidth.toDouble(), outputHeight.toDouble()),
                Point(0.0, outputHeight.toDouble())
            )

            // Get perspective transform matrix
            transform.release()
            transform = Imgproc.getPerspectiveTransform(corners, dstPoints)

            // Apply warp perspective
            Imgproc.warpPerspective(
                mat,
                result,
                transform,
                Size(outputWidth.toDouble(), outputHeight.toDouble())
            )

            // Convert back to bitmap
            val outputBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(result, outputBitmap)

            return outputBitmap
        } catch (e: Exception) {
            Log.e(TAG, "Perspective correction failed", e)
            throw e
        } finally {
            mat.release()
            result.release()
            dstPoints.release()
            transform.release()
        }
    }

    /**
     * Apply enhancement filter to an image.
     */
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

    /**
     * Save enhanced bitmap to file.
     */
    fun enhanceAndSave(imagePath: String, mode: String): String {
        val inputBitmap = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalArgumentException("Cannot decode image: $imagePath")

        val enhancedBitmap = enhance(inputBitmap, mode)

        // Create output file in filesDir (not cacheDir) for persistence
        val outputDir = context.filesDir
        val outputFile = File(outputDir, "enhanced_${System.currentTimeMillis()}.jpg")

        enhancedBitmap.compress(Bitmap.CompressFormat.JPEG, 90, FileOutputStream(outputFile))

        inputBitmap.recycle()
        enhancedBitmap.recycle()

        return outputFile.absolutePath
    }

    /**
     * Magic Color filter - enhances contrast and saturation.
     */
    private fun applyMagicColor(mat: Mat): Bitmap {
        // Convert RGBA to BGR (remove alpha channel for OpenCV processing)
        val bgr = Mat()
        Imgproc.cvtColor(mat, bgr, Imgproc.COLOR_RGBA2BGR)

        // Convert to LAB color space
        val lab = Mat()
        Imgproc.cvtColor(bgr, lab, Imgproc.COLOR_BGR2Lab)

        val channels = ArrayList<Mat>()
        Core.split(lab, channels)

        // Apply CLAHE to L channel (lightness)
        val clahe = Imgproc.createCLAHE(3.0, Size(8.0, 8.0))
        clahe.apply(channels[0], channels[0])

        // Merge back and release channel mats
        Core.merge(channels, lab)
        channels.forEach { it.release() }

        // Convert back to BGR
        val resultBgr = Mat()
        Imgproc.cvtColor(lab, resultBgr, Imgproc.COLOR_Lab2BGR)

        // Convert to HSV for saturation boost
        val hsv = Mat()
        Imgproc.cvtColor(resultBgr, hsv, Imgproc.COLOR_BGR2HSV_FULL)
        val hsvChannels = ArrayList<Mat>()
        Core.split(hsv, hsvChannels)

        // Increase saturation (S channel) by 20% with clamp to prevent overflow
        Core.multiply(hsvChannels[1], Scalar(1.2), hsvChannels[1])
        Core.min(hsvChannels[1], Scalar(255.0), hsvChannels[1]) // clamp to 255

        // Merge and release channel mats
        Core.merge(hsvChannels, hsv)
        hsvChannels.forEach { it.release() }

        // Convert back to BGR then RGBA
        Imgproc.cvtColor(hsv, resultBgr, Imgproc.COLOR_HSV2BGR_FULL)
        val result = Mat()
        Imgproc.cvtColor(resultBgr, result, Imgproc.COLOR_BGR2RGBA)

        val output = Bitmap.createBitmap(result.cols(), result.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(result, output)

        // Cleanup
        mat.release()
        bgr.release()
        lab.release()
        resultBgr.release()
        hsv.release()

        return output
    }

    /**
     * Grayscale filter.
     */
    private fun applyGrayscale(mat: Mat): Bitmap {
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)

        // Convert back to 4-channel for consistency
        val result = Mat()
        Imgproc.cvtColor(gray, result, Imgproc.COLOR_GRAY2RGBA)

        val output = Bitmap.createBitmap(result.cols(), result.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(result, output)

        mat.release()
        gray.release()
        result.release()

        return output
    }

    /**
     * Black & White (binary threshold) filter.
     */
    private fun applyBlackWhite(mat: Mat): Bitmap {
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)

        val result = Mat()
        // Adaptive threshold for better document scanning
        Imgproc.adaptiveThreshold(
            gray,
            result,
            255.0,
            Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
            Imgproc.THRESH_BINARY,
            11, // block size
            2.0  // constant
        )

        // Convert to RGBA for consistency
        val rgba = Mat()
        Imgproc.cvtColor(result, rgba, Imgproc.COLOR_GRAY2RGBA)

        val output = Bitmap.createBitmap(rgba.cols(), rgba.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(rgba, output)

        mat.release()
        gray.release()
        result.release()
        rgba.release()

        return output
    }

    /**
     * Whiteboard filter - optimized for whiteboard capture.
     */
    private fun applyWhiteboard(mat: Mat): Bitmap {
        val gray = Mat()
        Imgproc.cvtColor(mat, gray, Imgproc.COLOR_RGBA2GRAY)

        // Reduce noise
        val blurred = Mat()
        Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)

        // Normalize contrast
        val normalized = Mat()
        Core.normalize(blurred, normalized, 0.0, 255.0, Core.NORM_MINMAX)

        // Apply mild threshold
        val result = Mat()
        Imgproc.threshold(normalized, result, 180.0, 255.0, Imgproc.THRESH_TRUNC)

        // Brighten
        Core.add(result, Scalar(30.0), result)

        // Convert to RGBA
        val rgba = Mat()
        Imgproc.cvtColor(result, rgba, Imgproc.COLOR_GRAY2RGBA)

        val output = Bitmap.createBitmap(rgba.cols(), rgba.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(rgba, output)

        mat.release()
        gray.release()
        blurred.release()
        normalized.release()
        result.release()
        rgba.release()

        return output
    }

    /**
     * Build a PDF from a list of image paths.
     */
    fun buildPdfNative(imagePaths: List<String>, title: String): String {
        if (imagePaths.isEmpty()) {
            throw IllegalArgumentException("No images provided for PDF generation")
        }

        // Use filesDir as primary, external as fallback
        val outputDir = context.filesDir
        val pdfFile = File(outputDir, "${sanitizeTitle(title)}_${System.currentTimeMillis()}.pdf")

        val pdfDocument = PdfDocument()

        try {
            for ((index, imagePath) in imagePaths.withIndex()) {
                val bitmap = BitmapFactory.decodeFile(imagePath)
                    ?: throw IllegalArgumentException("Cannot decode image: $imagePath")

                // Scale bitmap to fit A4 page while maintaining aspect ratio
                val scaledBitmap = scaleBitmapToA4(bitmap)

                val pageInfo = PdfDocument.PageInfo.Builder(
                    scaledBitmap.width,
                    scaledBitmap.height,
                    index + 1
                ).create()

                val page = pdfDocument.startPage(pageInfo)
                page.canvas.drawBitmap(scaledBitmap, 0f, 0f, null)
                pdfDocument.finishPage(page)

                bitmap.recycle()
                scaledBitmap.recycle()
            }

            // Write PDF to file
            FileOutputStream(pdfFile).use { outputStream ->
                pdfDocument.writeTo(outputStream)
            }

            return pdfFile.absolutePath
        } finally {
            pdfDocument.close()
        }
    }

    /**
     * Extract text from an image using ML Kit OCR.
     */
    fun extractText(imagePath: String, onResult: (String) -> Unit) {
        val file = File(imagePath)
        if (!file.exists()) {
            onResult("")
            return
        }

        val image = InputImage.fromFilePath(context, Uri.fromFile(file))
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                onResult(visionText.text)
                recognizer.close()
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "OCR failed", e)
                onResult("")
                recognizer.close()
            }
    }

    // Helper functions

    /**
     * Convert ImageProxy to Bitmap with proper rotation handling.
     * Uses copyPixelsFromBuffer for RGBA_8888 format.
     */
    private fun ImageProxy.toBitmap(): Bitmap {
        // Create bitmap with correct dimensions and format
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

        // Copy pixels directly from buffer (RGBA_8888 format)
        val buffer = planes[0].buffer
        bitmap.copyPixelsFromBuffer(buffer)

        // Apply rotation if needed
        val rotationDegrees = imageInfo.rotationDegrees
        if (rotationDegrees != 0) {
            val matrix = Matrix().apply {
                postRotate(rotationDegrees.toFloat())
            }
            val rotatedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            bitmap.recycle()
            return rotatedBitmap
        }

        return bitmap
    }

    private fun flattenCorners(corners: MatOfPoint2f): List<Double> {
        return corners.toArray().flatMap { point ->
            listOf(point.x, point.y)
        }
    }

    private fun deflattenCorners(flat: List<Double>): MatOfPoint2f {
        val points = flat.chunked(2).map { (x, y) -> Point(x, y) }.toTypedArray()
        return MatOfPoint2f(*points)
    }

    private fun distance(p1: Point, p2: Point): Double {
        return Math.sqrt(Math.pow(p2.x - p1.x, 2.0) + Math.pow(p2.y - p1.y, 2.0))
    }

    private fun limitSize(width: Int, height: Int): Pair<Int, Int> {
        val maxDim = maxOf(width, height)
        if (maxDim <= MAX_OUTPUT_SIZE) {
            return Pair(width, height)
        }

        val scale = MAX_OUTPUT_SIZE.toDouble() / maxDim
        return Pair((width * scale).toInt(), (height * scale).toInt())
    }

    private fun scaleBitmapToA4(bitmap: Bitmap): Bitmap {
        val aspectRatio = bitmap.width.toDouble() / bitmap.height.toDouble()
        val a4AspectRatio = 210.0 / 297.0 // A4 dimensions in mm

        val targetWidth: Int
        val targetHeight: Int

        if (aspectRatio > a4AspectRatio) {
            // Wider than A4
            targetWidth = 2480
            targetHeight = (targetWidth / aspectRatio).toInt()
        } else {
            // Taller than A4
            targetHeight = 3508
            targetWidth = (targetHeight * aspectRatio).toInt()
        }

        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }

    private fun sanitizeTitle(title: String): String {
        return title.replace(Regex("[^\\w\\s-]"), "").trim().replace(" ", "_")
    }

    /**
     * Get current frame dimensions for overlay scaling.
     */
    fun getFrameDimensions(): Pair<Int, Int> {
        return Pair(currentFrameWidth, currentFrameHeight)
    }
}
