package com.gemify.gemmafy_mobile

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import androidx.work.WorkManager
import com.gemify.gemmafy_mobile.download.ModelDownloadManager
import com.gemify.gemmafy_mobile.inference.InferenceKeepAliveService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingStartArguments: Map<*, *>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Supprime seulement les anciennes tâches du downloader FlutterGemma.
        // Notre nouveau Worker utilise un autre tag et n'est pas annulé.
        WorkManager.getInstance(applicationContext)
            .cancelAllWorkByTag("BackgroundDownloader")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INFERENCE_KEEP_ALIVE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(
                            applicationContext,
                            InferenceKeepAliveService::class.java,
                        )
                        ContextCompat.startForegroundService(
                            applicationContext,
                            intent,
                        )
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error(
                            "inference_service_start_failed",
                            error.message ?: "Service de génération indisponible.",
                            null,
                        )
                    }
                }

                "stop" -> {
                    try {
                        val intent = Intent(
                            applicationContext,
                            InferenceKeepAliveService::class.java,
                        )
                        applicationContext.stopService(intent)
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error(
                            "inference_service_stop_failed",
                            error.message ?: "Impossible d’arrêter le service.",
                            null,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MODEL_DOWNLOAD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startModelDownload" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments == null) {
                        result.error(
                            "invalid_arguments",
                            "Arguments du téléchargement absents.",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    startWithNotificationPermission(arguments, result)
                }

                "getModelDownloadState" -> {
                    result.success(ModelDownloadManager.state(applicationContext))
                }

                "cancelModelDownload" -> {
                    ModelDownloadManager.cancel(applicationContext)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startWithNotificationPermission(
        arguments: Map<*, *>,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionResult != null) {
                result.error(
                    "permission_request_in_progress",
                    "Une demande de permission est déjà ouverte.",
                    null,
                )
                return
            }

            pendingPermissionResult = result
            pendingStartArguments = arguments
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
            return
        }

        enqueue(arguments, result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return

        val result = pendingPermissionResult
        val arguments = pendingStartArguments
        pendingPermissionResult = null
        pendingStartArguments = null

        if (result == null || arguments == null) return

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        if (!granted) {
            result.error(
                "notification_permission_denied",
                "Autorisez les notifications pour afficher le pourcentage " +
                    "pendant le téléchargement en arrière-plan.",
                null,
            )
            return
        }

        enqueue(arguments, result)
    }

    private fun enqueue(
        arguments: Map<*, *>,
        result: MethodChannel.Result,
    ) {
        val url = arguments["url"]?.toString()
        val fileName = arguments["fileName"]?.toString()
        val expectedTotal = when (val raw = arguments["expectedTotalBytes"]) {
            is Number -> raw.toLong()
            else -> raw?.toString()?.toLongOrNull() ?: 0L
        }

        if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error(
                "invalid_arguments",
                "URL ou nom de fichier invalide.",
                null,
            )
            return
        }

        try {
            val state = ModelDownloadManager.start(
                context = applicationContext,
                url = url,
                fileName = fileName,
                expectedTotalBytes = expectedTotal,
            )
            result.success(state)
        } catch (error: Throwable) {
            result.error(
                "download_start_failed",
                error.message ?: "Impossible de démarrer le téléchargement.",
                null,
            )
        }
    }

    companion object {
        private const val MODEL_DOWNLOAD_CHANNEL = "gemmafy/model_download"
        private const val INFERENCE_KEEP_ALIVE_CHANNEL =
            "gemmafy/inference_keep_alive"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4100
    }
}
