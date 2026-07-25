package com.gemify.gemmafy_mobile.download

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.io.EOFException
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

class ModelDownloadWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {

    private val notificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun doWork(): Result {
        val url = inputData.getString(ModelDownloadManager.KEY_URL)
            ?: return failure("Adresse du modèle absente.")
        val fileName = inputData.getString(ModelDownloadManager.KEY_FILE_NAME)
            ?: return failure("Nom du modèle absent.")
        val expectedTotal = inputData.getLong(
            ModelDownloadManager.KEY_EXPECTED_TOTAL,
            0,
        )

        createNotificationChannel()

        val partFile = ModelDownloadManager.partialFile(applicationContext, fileName)
        val completeFile = ModelDownloadManager.completeFile(applicationContext, fileName)

        if (completeFile.exists() &&
            (expectedTotal <= 0 || completeFile.length() == expectedTotal)
        ) {
            markCompleted(completeFile, completeFile.length())
            return Result.success(
                workDataOf(ModelDownloadManager.PREF_FILE_PATH to completeFile.absolutePath),
            )
        }

        var totalBytes = ModelDownloadManager.prefs(applicationContext)
            .getLong(ModelDownloadManager.PREF_TOTAL, expectedTotal)
            .takeIf { it > 0 } ?: expectedTotal
        var consecutiveFailures = 0

        updateProgress(
            status = ModelDownloadManager.STATUS_DOWNLOADING,
            downloaded = if (partFile.exists()) partFile.length() else 0,
            total = totalBytes,
            speed = 0,
            message = "Démarrage du téléchargement",
        )

        while (!isStopped) {
            val offset = if (partFile.exists()) partFile.length() else 0L

            if (totalBytes > 0 && offset == totalBytes) {
                return finishFile(partFile, completeFile, totalBytes)
            }

            try {
                val chunkResult = downloadOneChunk(
                    sourceUrl = url,
                    partFile = partFile,
                    offset = offset,
                    knownTotal = totalBytes,
                )

                totalBytes = chunkResult.totalBytes
                consecutiveFailures = 0

                if (chunkResult.completed) {
                    return finishFile(partFile, completeFile, totalBytes)
                }
            } catch (error: NonRetryableDownloadException) {
                return failure(error.message ?: "Erreur HTTP non récupérable.")
            } catch (error: ResumeSafetyException) {
                // Ne jamais supprimer le .part : l'utilisateur garde ses octets.
                return failure(error.message ?: "Reprise sécurisée impossible.")
            } catch (error: Exception) {
                if (isStopped) break

                consecutiveFailures += 1
                val savedBytes = if (partFile.exists()) partFile.length() else 0
                val waitSeconds = min(
                    60,
                    max(2, 2.0.pow(min(consecutiveFailures, 5)).toInt()),
                )

                updateProgress(
                    status = ModelDownloadManager.STATUS_WAITING,
                    downloaded = savedBytes,
                    total = totalBytes,
                    speed = 0,
                    message = "Connexion interrompue · reprise dans ${waitSeconds}s",
                )

                if (!sleepInterruptibly(waitSeconds * 1000L)) break
            }
        }

        val saved = if (partFile.exists()) partFile.length() else 0
        ModelDownloadManager.saveState(
            context = applicationContext,
            status = ModelDownloadManager.STATUS_WAITING,
            downloadedBytes = saved,
            totalBytes = totalBytes,
            speedBytesPerSecond = 0,
            filePath = null,
            error = null,
        )
        return Result.retry()
    }

    override fun onStopped() {
        super.onStopped()
        val prefs = ModelDownloadManager.prefs(applicationContext)
        val currentStatus = prefs.getString(
            ModelDownloadManager.PREF_STATUS,
            ModelDownloadManager.STATUS_IDLE,
        )

        if (currentStatus != ModelDownloadManager.STATUS_COMPLETED &&
            currentStatus != ModelDownloadManager.STATUS_CANCELLED &&
            currentStatus != ModelDownloadManager.STATUS_ERROR
        ) {
            ModelDownloadManager.saveState(
                context = applicationContext,
                status = ModelDownloadManager.STATUS_WAITING,
                downloadedBytes = prefs.getLong(ModelDownloadManager.PREF_DOWNLOADED, 0),
                totalBytes = prefs.getLong(ModelDownloadManager.PREF_TOTAL, 0),
                speedBytesPerSecond = 0,
                filePath = null,
                error = null,
            )
        }
    }

    private fun downloadOneChunk(
        sourceUrl: String,
        partFile: File,
        offset: Long,
        knownTotal: Long,
    ): ChunkResult {
        val requestedEnd = offset + CHUNK_SIZE_BYTES - 1
        val prefs = ModelDownloadManager.prefs(applicationContext)
        val ifRange = prefs.getString(ModelDownloadManager.PREF_ETAG, null)
            ?: prefs.getString(ModelDownloadManager.PREF_LAST_MODIFIED, null)

        val opened = openRangedConnection(
            sourceUrl = sourceUrl,
            start = offset,
            end = requestedEnd,
            ifRange = ifRange,
        )
        val connection = opened.connection

        try {
            val status = connection.responseCode

            if (status == HttpURLConnection.HTTP_UNAUTHORIZED ||
                status == HttpURLConnection.HTTP_FORBIDDEN ||
                status == HttpURLConnection.HTTP_NOT_FOUND
            ) {
                throw NonRetryableDownloadException("HTTP $status")
            }

            if (status == HTTP_RANGE_NOT_SATISFIABLE) {
                val total = parseUnsatisfiedTotal(
                    connection.getHeaderField("Content-Range"),
                )
                if (total != null && total == offset && offset > 0) {
                    return ChunkResult(totalBytes = total, completed = true)
                }
                throw ResumeSafetyException(
                    "Le serveur a refusé la reprise au byte $offset. " +
                        "Le fichier partiel a été conservé.",
                )
            }

            if (status != HttpURLConnection.HTTP_PARTIAL) {
                throw ResumeSafetyException(
                    "Le serveur n'a pas répondu en HTTP 206 au byte $offset. " +
                        "Aucun retour à 0 % n'a été effectué.",
                )
            }

            val range = parseContentRange(connection.getHeaderField("Content-Range"))
                ?: throw IOException("En-tête Content-Range absent.")

            if (range.start != offset) {
                throw ResumeSafetyException(
                    "Le serveur a repris au byte ${range.start} au lieu de $offset.",
                )
            }

            val totalBytes = range.total
            if (knownTotal > 0 && totalBytes != knownTotal) {
                throw ResumeSafetyException(
                    "La taille distante a changé ($knownTotal → $totalBytes). " +
                        "Le fichier partiel est conservé.",
                )
            }

            validateRemoteIdentity(connection)

            val etag = connection.getHeaderField("ETag")
            val lastModified = connection.getHeaderField("Last-Modified")
            prefs.edit()
                .putLong(ModelDownloadManager.PREF_TOTAL, totalBytes)
                .apply {
                    if (!etag.isNullOrBlank()) {
                        putString(ModelDownloadManager.PREF_ETAG, etag)
                    }
                    if (!lastModified.isNullOrBlank()) {
                        putString(
                            ModelDownloadManager.PREF_LAST_MODIFIED,
                            lastModified,
                        )
                    }
                }
                .apply()

            partFile.parentFile?.mkdirs()
            val output = RandomAccessFile(partFile, "rw")
            output.seek(offset)

            var received = offset
            var lastUiUpdateAt = System.currentTimeMillis()
            var speedWindowStartedAt = lastUiUpdateAt
            var speedWindowStartedBytes = received

            try {
                connection.inputStream.use { input ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (!isStopped) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue

                        output.write(buffer, 0, count)
                        received += count

                        val now = System.currentTimeMillis()
                        if (now - lastUiUpdateAt >= UI_UPDATE_INTERVAL_MS ||
                            received >= totalBytes
                        ) {
                            val elapsed = max(1, now - speedWindowStartedAt)
                            val speed =
                                ((received - speedWindowStartedBytes) * 1000L) / elapsed

                            updateProgress(
                                status = ModelDownloadManager.STATUS_DOWNLOADING,
                                downloaded = received,
                                total = totalBytes,
                                speed = speed,
                                message = "Téléchargement du modèle Gemma",
                            )

                            lastUiUpdateAt = now
                            if (now - speedWindowStartedAt >= SPEED_WINDOW_MS) {
                                speedWindowStartedAt = now
                                speedWindowStartedBytes = received
                            }
                        }
                    }
                }
            } finally {
                output.fd.sync()
                output.close()
            }

            if (isStopped) {
                throw IOException("Worker interrompu par Android.")
            }

            val actualLength = partFile.length()
            if (actualLength > totalBytes) {
                throw ResumeSafetyException(
                    "Le fichier partiel dépasse la taille attendue.",
                )
            }

            if (actualLength >= totalBytes) {
                return ChunkResult(totalBytes = totalBytes, completed = true)
            }

            val expectedAfterChunk = min(range.end + 1, totalBytes)
            if (actualLength < expectedAfterChunk) {
                // Les octets reçus sont déjà synchronisés. La prochaine connexion
                // repart exactement depuis actualLength.
                throw EOFException(
                    "Fin de flux inattendue : $actualLength / $expectedAfterChunk.",
                )
            }

            return ChunkResult(totalBytes = totalBytes, completed = false)
        } finally {
            connection.disconnect()
        }
    }

    private fun openRangedConnection(
        sourceUrl: String,
        start: Long,
        end: Long,
        ifRange: String?,
    ): OpenedConnection {
        var currentUrl = URL(sourceUrl)

        repeat(MAX_REDIRECTS + 1) {
            val connection = currentUrl.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.useCaches = false
            connection.setRequestProperty("Accept-Encoding", "identity")
            connection.setRequestProperty("User-Agent", "Gemmafy-Android/2.0")
            connection.setRequestProperty("Range", "bytes=$start-$end")
            connection.setRequestProperty("Connection", "close")
            if (!ifRange.isNullOrBlank()) {
                connection.setRequestProperty("If-Range", ifRange)
            }

            val status = connection.responseCode
            if (status !in REDIRECT_CODES) {
                return OpenedConnection(connection)
            }

            val location = connection.getHeaderField("Location")
            connection.disconnect()
            if (location.isNullOrBlank()) {
                throw IOException("Redirection HTTP sans en-tête Location.")
            }
            currentUrl = URL(currentUrl, location)
        }

        throw IOException("Trop de redirections HTTP.")
    }

    private fun validateRemoteIdentity(connection: HttpURLConnection) {
        val prefs = ModelDownloadManager.prefs(applicationContext)
        val oldEtag = prefs.getString(ModelDownloadManager.PREF_ETAG, null)
        val oldLastModified =
            prefs.getString(ModelDownloadManager.PREF_LAST_MODIFIED, null)
        val newEtag = connection.getHeaderField("ETag")
        val newLastModified = connection.getHeaderField("Last-Modified")

        if (!oldEtag.isNullOrBlank() &&
            !newEtag.isNullOrBlank() &&
            oldEtag != newEtag
        ) {
            throw ResumeSafetyException(
                "Le fichier distant a changé (ETag différent). " +
                    "La progression locale est conservée.",
            )
        }

        if (oldEtag.isNullOrBlank() &&
            !oldLastModified.isNullOrBlank() &&
            !newLastModified.isNullOrBlank() &&
            oldLastModified != newLastModified
        ) {
            throw ResumeSafetyException(
                "Le fichier distant a changé (Last-Modified différent). " +
                    "La progression locale est conservée.",
            )
        }
    }

    private fun finishFile(
        partFile: File,
        completeFile: File,
        totalBytes: Long,
    ): Result {
        if (!partFile.exists() || partFile.length() != totalBytes) {
            return failure(
                "Taille finale invalide : ${partFile.length()} / $totalBytes octets.",
            )
        }

        if (completeFile.exists()) completeFile.delete()
        if (!partFile.renameTo(completeFile)) {
            partFile.inputStream().use { input ->
                completeFile.outputStream().use { output -> input.copyTo(output) }
            }
            if (completeFile.length() != totalBytes) {
                completeFile.delete()
                return failure("Copie finale incomplète.")
            }
            partFile.delete()
        }

        markCompleted(completeFile, totalBytes)
        showCompletedNotification()

        return Result.success(
            workDataOf(ModelDownloadManager.PREF_FILE_PATH to completeFile.absolutePath),
        )
    }

    private fun markCompleted(file: File, totalBytes: Long) {
        ModelDownloadManager.saveState(
            context = applicationContext,
            status = ModelDownloadManager.STATUS_COMPLETED,
            downloadedBytes = totalBytes,
            totalBytes = totalBytes,
            speedBytesPerSecond = 0,
            filePath = file.absolutePath,
            error = null,
        )
        setProgressAsync(
            workDataOf(
                ModelDownloadManager.PREF_STATUS to ModelDownloadManager.STATUS_COMPLETED,
                ModelDownloadManager.PREF_DOWNLOADED to totalBytes,
                ModelDownloadManager.PREF_TOTAL to totalBytes,
            ),
        )
    }

    private fun updateProgress(
        status: String,
        downloaded: Long,
        total: Long,
        speed: Long,
        message: String,
    ) {
        ModelDownloadManager.saveState(
            context = applicationContext,
            status = status,
            downloadedBytes = downloaded,
            totalBytes = total,
            speedBytesPerSecond = speed,
            filePath = null,
            error = null,
        )

        setProgressAsync(
            workDataOf(
                ModelDownloadManager.PREF_STATUS to status,
                ModelDownloadManager.PREF_DOWNLOADED to downloaded,
                ModelDownloadManager.PREF_TOTAL to total,
                ModelDownloadManager.PREF_SPEED to speed,
            ),
        )

        setForegroundAsync(
            createForegroundInfo(
                downloaded = downloaded,
                total = total,
                message = message,
            ),
        ).get()
    }

    private fun failure(message: String): Result {
        val prefs = ModelDownloadManager.prefs(applicationContext)
        ModelDownloadManager.saveState(
            context = applicationContext,
            status = ModelDownloadManager.STATUS_ERROR,
            downloadedBytes = prefs.getLong(ModelDownloadManager.PREF_DOWNLOADED, 0),
            totalBytes = prefs.getLong(ModelDownloadManager.PREF_TOTAL, 0),
            speedBytesPerSecond = 0,
            filePath = null,
            error = message,
        )
        return Result.failure(workDataOf(ModelDownloadManager.PREF_ERROR to message))
    }

    private fun createForegroundInfo(
        downloaded: Long,
        total: Long,
        message: String,
    ): ForegroundInfo {
        val percentage = if (total > 0) {
            ((downloaded * 100L) / total).toInt().coerceIn(0, 100)
        } else {
            0
        }

        val cancelIntent = WorkManager.getInstance(applicationContext)
            .createCancelPendingIntent(id)

        val body = if (total > 0) {
            "$percentage %  •  ${formatBytes(downloaded)} / ${formatBytes(total)}"
        } else {
            "$percentage %"
        }

        val notification = NotificationCompat.Builder(
            applicationContext,
            NOTIFICATION_CHANNEL_ID,
        )
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(message)
            .setContentText(body)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(100, percentage, total <= 0)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Annuler",
                cancelIntent,
            )
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun showCompletedNotification() {
        val notification = NotificationCompat.Builder(
            applicationContext,
            NOTIFICATION_CHANNEL_ID,
        )
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Modèle Gemma téléchargé")
            .setContentText("100 % · prêt à être installé dans Gemmafy")
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()

        notificationManager.notify(COMPLETED_NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Téléchargement du modèle IA",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Progression du téléchargement hors ligne de Gemma"
            setSound(null, null)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun sleepInterruptibly(milliseconds: Long): Boolean {
        var remaining = milliseconds
        while (remaining > 0 && !isStopped) {
            val slice = min(1000L, remaining)
            try {
                Thread.sleep(slice)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
            remaining -= slice
        }
        return !isStopped
    }

    private fun parseContentRange(header: String?): ByteRange? {
        if (header.isNullOrBlank()) return null
        val match = CONTENT_RANGE_REGEX.matchEntire(header.trim()) ?: return null
        return ByteRange(
            start = match.groupValues[1].toLong(),
            end = match.groupValues[2].toLong(),
            total = match.groupValues[3].toLong(),
        )
    }

    private fun parseUnsatisfiedTotal(header: String?): Long? {
        if (header.isNullOrBlank()) return null
        return UNSATISFIED_RANGE_REGEX.matchEntire(header.trim())
            ?.groupValues
            ?.get(1)
            ?.toLongOrNull()
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes o"
        val units = arrayOf("Ko", "Mo", "Go", "To")
        var value = bytes.toDouble()
        var unit = -1
        while (value >= 1024 && unit < units.lastIndex) {
            value /= 1024
            unit += 1
        }
        return String.format(Locale.FRANCE, "%.2f %s", value, units[unit])
    }

    private data class ByteRange(
        val start: Long,
        val end: Long,
        val total: Long,
    )

    private data class ChunkResult(
        val totalBytes: Long,
        val completed: Boolean,
    )

    private data class OpenedConnection(
        val connection: HttpURLConnection,
    )

    private class NonRetryableDownloadException(message: String) :
        IOException(message)

    private class ResumeSafetyException(message: String) :
        IOException(message)

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "gemmafy_model_download"
        private const val NOTIFICATION_ID = 41001
        private const val COMPLETED_NOTIFICATION_ID = 41002

        private const val CHUNK_SIZE_BYTES = 8L * 1024L * 1024L
        private const val BUFFER_SIZE = 256 * 1024
        private const val MAX_REDIRECTS = 10
        private const val CONNECT_TIMEOUT_MS = 45_000
        private const val READ_TIMEOUT_MS = 90_000
        private const val UI_UPDATE_INTERVAL_MS = 1_000L
        private const val SPEED_WINDOW_MS = 4_000L
        private const val HTTP_RANGE_NOT_SATISFIABLE = 416

        private val REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
        private val CONTENT_RANGE_REGEX =
            Regex("bytes\\s+(\\d+)-(\\d+)/(\\d+)")
        private val UNSATISFIED_RANGE_REGEX =
            Regex("bytes\\s+\\*/(\\d+)")
    }
}
