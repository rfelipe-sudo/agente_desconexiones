package com.creacionestecnologicas.agente_desconexiones

import android.app.ActivityManager
import android.content.Context

object AppForeground {
    /** true si la app está visible (primer plano o parcialmente visible). */
    fun isInForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val processes = am.runningAppProcesses ?: return false
        for (process in processes) {
            if (process.processName != context.packageName) continue
            return process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
        }
        return false
    }
}
