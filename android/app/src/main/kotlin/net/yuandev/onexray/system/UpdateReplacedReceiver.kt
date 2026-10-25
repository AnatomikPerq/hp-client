package net.yuandev.onexray.system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.edit
import com.elvishew.xlog.XLog
import net.yuandev.onexray.vpn.VpnController

/**
 * Replacing the package kills both processes and with them the tunnel. When
 * the update started while the VPN ran, the updated App brings it back like
 * the Windows installer does: MY_PACKAGE_REPLACED may start a foreground
 * service from the background.
 */
class UpdateReplacedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(KEY_RECONNECT, false)) return
        preferences.edit(commit = true) { remove(KEY_RECONNECT) }
        XLog.init()
        try {
            val result = VpnController.startSavedVpn(context, automation = false)
            if (result != VpnController.SavedStartResult.STARTED) {
                XLog.w("VPN not restarted after the update: $result ${VpnController.lastError}")
            }
        } catch (error: Exception) {
            XLog.e("VPN restart after the update failed", error)
        }
    }

    companion object {
        private const val PREFERENCES = "app_update"
        private const val KEY_RECONNECT = "reconnect"

        fun setReconnect(context: Context, reconnect: Boolean) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit(commit = true) {
                if (reconnect) putBoolean(KEY_RECONNECT, true) else remove(KEY_RECONNECT)
            }
        }
    }
}
