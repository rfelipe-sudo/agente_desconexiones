package com.creacionestecnologicas.agente_desconexiones

/**
 * Indica si [MainActivity] está en primer plano (onResume activo).
 * Más fiable que [AppForeground]: al despertar por FCM el proceso puede
 * reportar IMPORTANCE_FOREGROUND aunque no haya UI visible.
 */
object AppVisibility {
    @Volatile
    var activityResumed: Boolean = false

    fun isUiVisible(): Boolean = activityResumed
}
