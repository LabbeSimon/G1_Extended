package fr.simonlabbe.g1extended

import android.app.Application

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(LifecycleDetector.activityLifecycleCallbacks)
        CrashTrail.install(this)
    }
}