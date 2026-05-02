package com.karimpichara.turingandroid

import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class LatestFrameProcessor<T>(
    private val executor: Executor,
    private val processFrame: (T) -> Unit,
) {
    private val latestFrame = AtomicReference<T?>(null)
    private val isProcessing = AtomicBoolean(false)

    fun submit(frame: T) {
        latestFrame.set(frame)
        maybeStartProcessing()
    }

    private fun maybeStartProcessing() {
        if (!isProcessing.compareAndSet(false, true)) {
            return
        }

        executor.execute {
            try {
                while (true) {
                    val frame = latestFrame.getAndSet(null) ?: break
                    processFrame(frame)
                }
            } finally {
                isProcessing.set(false)
                if (latestFrame.get() != null) {
                    maybeStartProcessing()
                }
            }
        }
    }
}
