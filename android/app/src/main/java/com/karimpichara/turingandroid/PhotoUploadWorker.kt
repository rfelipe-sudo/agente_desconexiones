package com.karimpichara.turingandroid

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class PhotoUploadWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val filePath = inputData.getString(KEY_FILE_PATH) ?: return Result.failure()
        val s3Key = inputData.getString(KEY_S3_KEY) ?: return Result.failure()

        val file = File(filePath)
        if (!file.exists()) return Result.success()

        val result = withContext(Dispatchers.IO) {
            S3Uploader.upload(file, s3Key)
        }

        return if (result.isSuccess) {
            file.delete()
            Result.success()
        } else {
            val exception = result.exceptionOrNull()
            if (exception is IllegalStateException) {
                Result.failure()
            } else {
                Result.retry()
            }
        }
    }

    companion object {
        const val KEY_FILE_PATH = "file_path"
        const val KEY_S3_KEY = "s3_key"
        const val WORK_TAG = "photo_upload"
    }
}
