package net.yuandev.onexray.system

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import com.elvishew.xlog.XLog
import net.yuandev.onexray.pigeon.AndroidSystemHostApi
import net.yuandev.onexray.pigeon.AndroidUpdateInstallState
import java.io.File

/** System screens the App hands the user to: the package installer, VPN settings. */
class AndroidSystemApi(private val context: Context) : AndroidSystemHostApi {
    /**
     * One-click update: Dart downloads the APK into `files/update/` and checks
     * its SHA-256; this opens the system installer for it. Android replaces
     * the package only when the signature matches the installed one.
     */
    override fun installUpdate(
        path: String,
        reconnect: Boolean,
        callback: (Result<AndroidUpdateInstallState>) -> Unit,
    ) {
        try {
            val file = File(path).canonicalFile
            val folder = File(context.filesDir, UPDATE_FOLDER).canonicalFile
            require(file.parentFile == folder && file.isFile && file.name.endsWith(".apk")) {
                "Not an update package"
            }
            if (!context.packageManager.canRequestPackageInstalls()) {
                context.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${context.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                callback(Result.success(AndroidUpdateInstallState.PERMISSION_REQUIRED))
                return
            }
            UpdateReplacedReceiver.setReconnect(context, reconnect)
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.update", file)
            context.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            callback(Result.success(AndroidUpdateInstallState.STARTED))
        } catch (error: Exception) {
            XLog.e("Update install failed", error)
            callback(Result.failure(error))
        }
    }

    override fun canInstallUpdates(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(context.packageManager.canRequestPackageInstalls()))
    }

    override fun clearUpdateReconnect(callback: (Result<Unit>) -> Unit) {
        UpdateReplacedReceiver.setReconnect(context, false)
        callback(Result.success(Unit))
    }

    override fun openVpnSettings(callback: (Result<Boolean>) -> Unit) {
        val opened = try {
            context.startActivity(
                Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
        callback(Result.success(opened))
    }

    companion object {
        const val UPDATE_FOLDER = "update"
    }
}
