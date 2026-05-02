package com.karimpichara.turingandroid

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

class DetectionOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    private var detections: List<DetectionResult> = emptyList()
    private var frameWidth: Int = 0
    private var frameHeight: Int = 0

    private val greenPaint = Paint().apply {
        color = Color.GREEN
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }

    private val yellowPaint = Paint().apply {
        color = Color.YELLOW
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }

    private val redPaint = Paint().apply {
        color = Color.RED
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }

    private val labelBackgroundPaint = Paint().apply {
        color = Color.parseColor("#CC000000")
        style = Paint.Style.FILL
    }

    private val labelTextPaint = Paint().apply {
        color = Color.WHITE
        textSize = 36f
    }

    fun updateDetections(detections: List<DetectionResult>, frameWidth: Int, frameHeight: Int) {
        this.detections = detections
        this.frameWidth = frameWidth
        this.frameHeight = frameHeight
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (frameWidth == 0 || frameHeight == 0 || detections.isEmpty()) return

        val viewW = width.toFloat()
        val viewH = height.toFloat()
        val frameW = frameWidth.toFloat()
        val frameH = frameHeight.toFloat()
        val viewArea = viewW * viewH

        val scale = maxOf(viewW / frameW, viewH / frameH)
        val dx = (viewW - frameW * scale) / 2f
        val dy = (viewH - frameH * scale) / 2f

        for (det in detections) {
            val mapped = RectF(
                det.bbox.left * scale + dx,
                det.bbox.top * scale + dy,
                det.bbox.right * scale + dx,
                det.bbox.bottom * scale + dy,
            )
            val mappedArea = mapped.height() * mapped.width()
//            val isConfirmed = det.convConf >= 0.5f
//            val boxPaint = if (isConfirmed) greenPaint else redPaint

//            if (mappedArea/viewArea <= .75 && mappedArea/viewArea >= .2) {
            canvas.drawRect(mapped, yellowPaint)
//            }
//
//            val label = "${55555} ${(.9 * 100).toInt()}%→${(.9 * 100).toInt()}%"
//            val textWidth = labelTextPaint.measureText(label)
//            val textHeight = labelTextPaint.fontMetrics.let { it.descent - it.ascent }
//
//            canvas.drawRect(
//                mapped.left,
//                mapped.top,
//                mapped.left + 275 + 8f,
//                mapped.top + 43 + 4f,
//                labelBackgroundPaint,
//            )

//            canvas.drawText(
//                label,
//                mapped.left + 4f,
//                mapped.top + textHeight - labelTextPaint.fontMetrics.descent,
//                labelTextPaint,
//            )
        }
    }
}
