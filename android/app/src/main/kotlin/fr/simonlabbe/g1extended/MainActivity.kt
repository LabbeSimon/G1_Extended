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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notifications.createNotificationChannels(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        BackgroundService.stopService(this, null)
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
