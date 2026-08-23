package fr.simonlabbe.g1extended

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import fr.simonlabbe.g1extended.cpp.Cpp
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Hosts the Flutter UI and exposes the few native capabilities Flutter cannot
 * reach on its own:
 *
 *  - LC3 audio decoding for the glasses microphone (native C++)
 *  - starting and stopping the background connection service
 *  - sending the app to the background instead of killing it
 *  - the battery optimisation exemption prompt
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val PACKAGE = "fr.simonlabbe.g1extended"

        const val CHANNEL_LC3 = "$PACKAGE/channel"
        const val CHANNEL_BACKGROUND = "$PACKAGE/background_service"
        const val CHANNEL_APP_RETAIN = "$PACKAGE/app_retain"
        const val CHANNEL_BATTERY = "$PACKAGE/battery_optimization"
        const val CHANNEL_INSTALL = "$PACKAGE/apk_install"
        const val CHANNEL_MEMORY = "$PACKAGE/memory"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notifications.createNotificationChannels(this)
    }

    override fun onDestroy() {
        super.onDestroy()

        // The background service is deliberately left running.
        //
        // It used to be stopped here, which defeated the one thing it
        // exists for: holding the Bluetooth link while the app is not on
        // screen. onDestroy fires when the activity goes away for any
        // reason — the user swiping it out of recents, the system
        // reclaiming it, or the process dying — so the glasses disconnected
        // every time, including as a second casualty of any crash. The
        // service stops when it is told to, from the app's own control, and
        // not before.
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Cpp.init()
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CHANNEL_LC3).setMethodCallHandler { call, result ->
            if (call.method == "decodeLC3") {
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.error("INVALID_ARGUMENT", "Data is null", null)
                } else {
                    result.success(Cpp.decodeLC3(data))
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, CHANNEL_BACKGROUND).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    BackgroundService.startService(this, call.arguments as Long)
                    result.success(null)
                }
                "stopService" -> {
                    BackgroundService.stopService(this, call.arguments as Long)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, CHANNEL_APP_RETAIN).setMethodCallHandler { call, result ->
            if (call.method == "sendToBackground") {
                moveTaskToBack(true)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // What the system will let this process have — asked before the
        // speech model meets a native loader that cannot fail politely.
        MethodChannel(messenger, CHANNEL_MEMORY).setMethodCallHandler { call, result ->
            if (call.method == "abis") {
                // Most preferred first, which is the order Android itself
                // uses when choosing which native libraries to load.
                result.success(android.os.Build.SUPPORTED_ABIS.toList())
            } else if (call.method == "state") {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                val info = android.app.ActivityManager.MemoryInfo()
                am.getMemoryInfo(info)
                result.success(
                    mapOf(
                        "availableBytes" to info.availMem,
                        "totalBytes" to info.totalMem,
                        "lowMemoryThresholdBytes" to info.threshold,
                        "systemLowMemory" to info.lowMemory,
                        "heapLimitMb" to am.largeMemoryClass,
                    )
                )
            } else {
                result.notImplemented()
            }
        }

        // In-app updates. Android never lets an app install silently — the
        // system's own sheet always confirms — but it does let one hand the
        // installer a downloaded APK, which spares the trip through the
        // browser and the Downloads folder.
        MethodChannel(messenger, CHANNEL_INSTALL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> {
                    result.success(
                        android.os.Build.VERSION.SDK_INT < 26 ||
                            packageManager.canRequestPackageInstalls()
                    )
                }
                "openInstallPermission" -> {
                    // The per-app "install unknown apps" switch. There is no
                    // dialog for it; the settings page is the only door.
                    val intent = android.content.Intent(
                        android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        android.net.Uri.parse("package:$PACKAGE"),
                    )
                    startActivity(intent)
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this, "$PACKAGE.fileprovider", java.io.File(path),
                        )
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, CHANNEL_BATTERY).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryOptimizationDisabled" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                }
                "requestDisableBatteryOptimization" -> {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = Uri.parse("package:$packageName")
                    result.success(
                        try {
                            startActivity(intent)
                            true
                        } catch (e: Exception) {
                            Log.w(TAG, "Battery optimisation screen unavailable", e)
                            false
                        }
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}
