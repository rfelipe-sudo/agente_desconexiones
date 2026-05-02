package com.karimpichara.turingandroid

import android.content.Context
import android.graphics.Bitmap
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.io.File
import java.util.concurrent.TimeUnit

object PhotoUploadManager {

    fun saveAndEnqueue(
        context: Context,
        bitmap: Bitmap,
        rut: String,
        boxType: String,
        convConf: Float,
        yoloConf: Float
    ): File? {
        val file = PhotoSaver.save(context, bitmap, rut, boxType, convConf, yoloConf) ?: return null
        enqueueUpload(context, file, boxType)
        return file
    }

    fun enqueueUpload(
        context: Context,
        file: File,
        boxType: String
    ) {
        val s3Key = PhotoSaver.generateS3Key(boxType, file.name)

        val inputData = Data.Builder()
            .putString(PhotoUploadWorker.KEY_FILE_PATH, file.absolutePath)
            .putString(PhotoUploadWorker.KEY_S3_KEY, s3Key)
            .build()

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val uploadWork = OneTimeWorkRequestBuilder<PhotoUploadWorker>()
            .setInputData(inputData)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(PhotoUploadWorker.WORK_TAG)
            .build()

        WorkManager.getInstance(context).enqueue(uploadWork)
    }
}
