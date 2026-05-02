package com.karimpichara.turingandroid

fun iou(a: FloatArray, b: FloatArray): Float {
    val x1 = maxOf(a[0], b[0])
    val y1 = maxOf(a[1], b[1])
    val x2 = minOf(a[2], b[2])
    val y2 = minOf(a[3], b[3])
    val intersection = maxOf(0f, x2 - x1) * maxOf(0f, y2 - y1)
    val areaA = (a[2] - a[0]) * (a[3] - a[1])
    val areaB = (b[2] - b[0]) * (b[3] - b[1])
    val union = areaA + areaB - intersection
    return if (union > 0f) intersection / union else 0f
}

fun nms(
    boxes: List<FloatArray>,
    scores: List<Float>,
    iouThreshold: Float,
): List<Int> {
    if (boxes.isEmpty()) return emptyList()
    val indices = boxes.indices.sortedByDescending { scores[it] }
    val suppressed = BooleanArray(boxes.size)
    val selected = mutableListOf<Int>()

    for (i in indices) {
        if (suppressed[i]) continue
        selected.add(i)
        for (j in indices) {
            if (suppressed[j] || j == i) continue
            if (iou(boxes[i], boxes[j]) > iouThreshold) {
                suppressed[j] = true
            }
        }
    }
    return selected
}
