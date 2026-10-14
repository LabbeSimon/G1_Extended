package fr.simonlabbe.g1extended

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Process
import android.util.Log
import androidx.annotation.RequiresApi
import java.io.File
import kotlin.system.exitProcess

/**
 * What Dart cannot see of the last time the app died.
 *
 * Two things end the process without any Dart handler running: a Java error
 * on a platform thread, which Flutter hands to the thread's uncaught
 * exception handler rather than to Dart, and anything native. The first is
 * written down here as it happens. For both, Android keeps its own account of
 * why the process ended, read back on the next launch.
 */
object CrashTrail {
    private const val JAVA_CRASH_FILE = "java-crash.txt"

    /** Writes an uncaught Java error down before the process goes. */
    fun install(context: Context) {
        val file = File(context.filesDir, JAVA_CRASH_FILE)
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                file.writeText(
                    "Thread: ${thread.name}\n\n${Log.getStackTraceString(error)}"
                )
            } catch (ignored: Throwable) {
                // Writing it down must never be what hides the crash.
            }
            if (previous != null) {
                previous.uncaughtException(thread, error)
            } else {
                Process.killProcess(Process.myPid())
                exitProcess(10)
            }
        }
    }

    /** The stack the last Java crash left, handed over once. */
    fun takeJavaCrash(context: Context): String? {
        val file = File(context.filesDir, JAVA_CRASH_FILE)
        if (!file.exists()) return null
        return try {
            file.readText()
        } catch (e: Exception) {
            null
        } finally {
            file.delete()
        }
    }

    /**
     * Android's account of the most recent end of this app's process. Null
     * before Android 11, which keeps none.
     */
    fun lastExit(context: Context): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val manager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exit = manager
            .getHistoricalProcessExitReasons(context.packageName, 0, 1)
            .firstOrNull() ?: return null
        return mapOf(
            "timestamp" to exit.timestamp,
            "reason" to reasonName(exit.reason),
            "status" to exit.status,
            "description" to exit.description,
            "importance" to exit.importance,
            "pssKb" to exit.pss,
            "rssKb" to exit.rss,
        )
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
        ApplicationExitInfo.REASON_OTHER -> "other"
        // Android 13's additions, as numbers: REASON_FREEZER,
        // REASON_PACKAGE_STATE_CHANGE and REASON_PACKAGE_UPDATED.
        14 -> "freezer"
        15 -> "package_state_change"
        16 -> "package_updated"
        else -> "unknown"
    }
}
