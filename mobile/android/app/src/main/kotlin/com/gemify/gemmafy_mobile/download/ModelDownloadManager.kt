package com.gemify.gemmafy_mobile.download

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.io.File
import java.util.concurrent.TimeUnit

object ModelDownloadManager {
    const val UNIQUE_WORK_NAME = "gemmafy-model-download"
    const val WORK_TAG = "gemmafy-model-download"
    const val PREFS_NAME = "gemmafy_model_download"

    const val KEY_URL = "url"
    const val KEY_FILE_NAME = "fileName"
    const val KEY_EXPECTED_TOTAL = "expectedTotalBytes"

    const val PREF_STATUS = "status"
    const val PREF_DOWNLOADED = "downloadedBytes"
    const val PREF_TOTAL = "totalBytes"
    const val PREF_SPEED = "speedBytesPerSecond"
    const val PREF_FILE_PATH = "filePath"
    const val PREF_ERROR = "error"
    const val PREF_ETAG = "etag"
    const val PREF_LAST_MODIFIED = "lastModified"

    const val STATUS_IDLE = "idle"
    const val STATUS_QUEUED = "queued"
    const val STATUS_DOWNLOADING = "downloading"
    const val STATUS_WAITING = "waiting"
    const val STATUS_COMPLETED = "completed"
    const val STATUS_ERROR = "error"
    const val STATUS_CANCELLED = "cancelled"

    fun start(
        context: Context,
        url: String,
        fileName: String,
        expectedTotalBytes: Long,
    ): Map<String, Any?> {
        migrateLegacyFile(context, fileName, expectedTotalBytes)

        val completeFile = completeFile(context, fileName)
        if (completeFile.exists() && completeFile.length() == expectedTotalBytes) {
            saveState(
                context = context,
                status = STATUS_COMPLETED,
                downloadedBytes = completeFile.length(),
                totalBytes = expectedTotalBytes,
                speedBytesPerSecond = 0,
                filePath = completeFile.absolutePath,
                error = null,
            )
            return state(context)
        }

        val current = state(context)
        val currentStatus = current[PREF_STATUS]?.toString()
        if (currentStatus != STATUS_DOWNLOADING && currentStatus != STATUS_WAITING) {
            val partial = partialFile(context, fileName)
            saveState(
                context = context,
                status = STATUS_QUEUED,
                downloadedBytes = if (partial.exists()) partial.length() else 0,
                totalBytes = expectedTotalBytes,
                speedBytesPerSecond = 0,
                filePath = null,
                error = null,
            )
        }

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = OneTimeWorkRequestBuilder<ModelDownloadWorker>()
            .setInputData(
                workDataOf(
                    KEY_URL to url,
                    KEY_FILE_NAME to fileName,
                    KEY_EXPECTED_TOTAL to expectedTotalBytes,
                ),
            )
            .setConstraints(constraints)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                10,
                TimeUnit.SECONDS,
            )
            .addTag(WORK_TAG)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request,
        )

        return state(context)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
        val prefs = prefs(context)
        val downloaded = prefs.getLong(PREF_DOWNLOADED, 0)
        val total = prefs.getLong(PREF_TOTAL, 0)
        saveState(
            context = context,
            status = STATUS_CANCELLED,
            downloadedBytes = downloaded,
            totalBytes = total,
            speedBytesPerSecond = 0,
            filePath = null,
            error = null,
        )
    }

    fun state(context: Context): Map<String, Any?> {
        val prefs = prefs(context)
        val status = prefs.getString(PREF_STATUS, STATUS_IDLE) ?: STATUS_IDLE
        val downloaded = prefs.getLong(PREF_DOWNLOADED, 0)
        val total = prefs.getLong(PREF_TOTAL, 0)

        return mapOf(
            PREF_STATUS to status,
            PREF_DOWNLOADED to downloaded,
            PREF_TOTAL to total,
            PREF_SPEED to prefs.getLong(PREF_SPEED, 0),
            PREF_FILE_PATH to prefs.getString(PREF_FILE_PATH, null),
            PREF_ERROR to prefs.getString(PREF_ERROR, null),
        )
    }

    fun saveState(
        context: Context,
        status: String,
        downloadedBytes: Long,
        totalBytes: Long,
        speedBytesPerSecond: Long,
        filePath: String?,
        error: String?,
    ) {
        val editor = prefs(context).edit()
            .putString(PREF_STATUS, status)
            .putLong(PREF_DOWNLOADED, downloadedBytes)
            .putLong(PREF_TOTAL, totalBytes)
            .putLong(PREF_SPEED, speedBytesPerSecond)

        if (filePath == null) editor.remove(PREF_FILE_PATH)
        else editor.putString(PREF_FILE_PATH, filePath)

        if (error == null) editor.remove(PREF_ERROR)
        else editor.putString(PREF_ERROR, error)

        editor.apply()
    }

    fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun modelDirectory(context: Context): File =
        File(context.filesDir, "models").apply { mkdirs() }

    fun partialFile(context: Context, fileName: String): File =
        File(modelDirectory(context), "$fileName.part")

    fun completeFile(context: Context, fileName: String): File =
        File(modelDirectory(context), fileName)

    /**
     * Récupère le fichier partiel laissé par l'ancien FlutterGemma dans
     * /data/user/0/<package>/app_flutter, sans jamais remplacer un fichier
     * partiel plus avancé.
     */
    private fun migrateLegacyFile(
        context: Context,
        fileName: String,
        expectedTotalBytes: Long,
    ) {
        val legacy = File(context.applicationInfo.dataDir, "app_flutter/$fileName")
        if (!legacy.exists() || legacy.length() <= 0) return

        val destination = if (legacy.length() == expectedTotalBytes) {
            completeFile(context, fileName)
        } else {
            partialFile(context, fileName)
        }

        if (destination.exists() && destination.length() >= legacy.length()) return

        destination.parentFile?.mkdirs()
        if (destination.exists()) destination.delete()

        if (!legacy.renameTo(destination)) {
            legacy.inputStream().use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            }
            if (destination.length() == legacy.length()) {
                legacy.delete()
            }
        }
    }
}
