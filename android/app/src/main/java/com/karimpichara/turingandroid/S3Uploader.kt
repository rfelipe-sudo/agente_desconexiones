package com.karimpichara.turingandroid

import com.amazonaws.auth.BasicAWSCredentials
import com.amazonaws.services.s3.AmazonS3Client
import com.amazonaws.services.s3.model.ObjectMetadata
import com.creacionestecnologicas.agente_desconexiones.BuildConfig
import java.io.File
import java.io.FileInputStream

object S3Uploader {

    private val client: AmazonS3Client? by lazy {
        val accessKey = BuildConfig.S3_ACCESS_KEY
        val secretKey = BuildConfig.S3_SECRET_KEY
        if (accessKey.isBlank() || secretKey.isBlank()) return@lazy null
        val credentials = BasicAWSCredentials(accessKey, secretKey)
        AmazonS3Client(credentials).apply {
            setEndpoint("https://s3.${BuildConfig.S3_REGION}.amazonaws.com")
        }
    }

    private val bucket: String = BuildConfig.S3_BUCKET

    fun upload(file: File, s3Key: String): Result<Unit> {
        val s3 = client ?: return Result.failure(IllegalStateException("S3 credentials not configured"))
        if (bucket.isBlank()) return Result.failure(IllegalStateException("S3 bucket not configured"))
        return try {
            val metadata = ObjectMetadata().apply {
                contentLength = file.length()
                contentType = "image/jpeg"
            }
            FileInputStream(file).use { stream ->
                s3.putObject(bucket, s3Key, stream, metadata)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
