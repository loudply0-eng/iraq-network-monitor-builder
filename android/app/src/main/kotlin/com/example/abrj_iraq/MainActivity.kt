package com.example.abrj_iraq

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.PhoneStateListener
import android.telephony.SubscriptionManager
import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // OTA installer compatibility fix: validate package/version and grant content URI access.
    private val CHANNEL = "com.abrjiraq/tower"
    private val displayInfoBySubscription = mutableMapOf<Int, Int>()
    private val displayInfoListeners = mutableMapOf<Int, PhoneStateListener>()
    private val displayInfoManagers = mutableMapOf<Int, TelephonyManager>()

    private fun startDisplayInfoListeners() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val baseManager =
                getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val subscriptionManager =
                getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            val activeIds = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                subscriptionManager.activeSubscriptionInfoList.orEmpty()
                    .map { it.subscriptionId }
                    .distinct()
            } else {
                emptyList()
            }
            val defaultId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                SubscriptionManager.getDefaultDataSubscriptionId()
            } else {
                SubscriptionManager.INVALID_SUBSCRIPTION_ID
            }
            val ids = (activeIds.ifEmpty { listOf(defaultId) }).distinct()

            for (subscriptionId in ids) {
                if (displayInfoListeners.containsKey(subscriptionId)) continue
                val perSimManager = if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                    subscriptionId != SubscriptionManager.INVALID_SUBSCRIPTION_ID
                ) {
                    baseManager.createForSubscriptionId(subscriptionId)
                } else {
                    baseManager
                }
                val listener = object : PhoneStateListener() {
                    override fun onDisplayInfoChanged(info: TelephonyDisplayInfo) {
                        displayInfoBySubscription[subscriptionId] = info.overrideNetworkType
                    }
                }
                perSimManager.listen(listener, PhoneStateListener.LISTEN_DISPLAY_INFO_CHANGED)
                displayInfoListeners[subscriptionId] = listener
                displayInfoManagers[subscriptionId] = perSimManager
            }
        } catch (_: SecurityException) {
            // Phone permission may not have been granted yet.
        } catch (_: Exception) {
            // Display overrides are optional; basic cell measurements still work.
        }
    }

    private fun stopDisplayInfoListeners() {
        for ((subscriptionId, listener) in displayInfoListeners) {
            try {
                displayInfoManagers[subscriptionId]?.listen(
                    listener,
                    PhoneStateListener.LISTEN_NONE
                )
            } catch (_: Exception) {
                // Ignore listener teardown failures.
            }
        }
        displayInfoListeners.clear()
        displayInfoManagers.clear()
    }

    override fun onResume() {
        super.onResume()
        startDisplayInfoListeners()
    }

    override fun onPause() {
        stopDisplayInfoListeners()
        super.onPause()
    }

    private fun wifiBand(frequencyMhz: Int): String {
        return when (frequencyMhz) {
            in 2400..2500 -> "2.4 GHz"
            in 4900..5895 -> "5 GHz"
            in 5925..7125 -> "6 GHz"
            else -> "Unknown"
        }
    }

    private fun wifiChannel(frequencyMhz: Int): Int? {
        return when {
            frequencyMhz == 2484 -> 14
            frequencyMhz in 2412..2472 -> (frequencyMhz - 2407) / 5
            frequencyMhz in 5000..5895 -> (frequencyMhz - 5000) / 5
            frequencyMhz in 5955..7115 -> (frequencyMhz - 5950) / 5
            else -> null
        }
    }

    private fun networkTypeLabel(
        telephonyManager: TelephonyManager,
        subscriptionId: Int = SubscriptionManager.INVALID_SUBSCRIPTION_ID
    ): String {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            telephonyManager.dataNetworkType
        } else {
            telephonyManager.networkType
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val overrideType = displayInfoBySubscription[subscriptionId]
                ?: displayInfoBySubscription[SubscriptionManager.INVALID_SUBSCRIPTION_ID]
            when (overrideType) {
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA -> return "5G NSA"
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_CA,
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_ADVANCED_PRO -> return "4G+"
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA_MMWAVE -> return "5G NSA mmWave"
                else -> Unit
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                overrideType == TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED
            ) {
                return "5G Advanced"
            }
        }
        return when (type) {
            TelephonyManager.NETWORK_TYPE_LTE -> "4G LTE"
            TelephonyManager.NETWORK_TYPE_NR -> "5G NR"
            TelephonyManager.NETWORK_TYPE_HSPAP,
            TelephonyManager.NETWORK_TYPE_HSPA,
            TelephonyManager.NETWORK_TYPE_HSUPA,
            TelephonyManager.NETWORK_TYPE_HSDPA,
            TelephonyManager.NETWORK_TYPE_UMTS -> "3G"
            TelephonyManager.NETWORK_TYPE_EDGE,
            TelephonyManager.NETWORK_TYPE_GPRS -> "2G"
            else -> "غير معروف"
        }
    }

    private fun bandLabel(bands: IntArray?): String? {
        val validBands = bands?.filter { it > 0 }?.distinct().orEmpty()
        return if (validBands.isEmpty()) null else validBands.joinToString(" + ") { "B$it" }
    }

    private fun cellSnapshot(
        telephonyManager: TelephonyManager,
        subscriptionId: Int = SubscriptionManager.INVALID_SUBSCRIPTION_ID
    ): Map<String, Any?> {
        val cells = telephonyManager.allCellInfo.orEmpty()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val registeredNr = cells.filterIsInstance<CellInfoNr>()
                .firstOrNull { it.isRegistered }
            if (registeredNr != null) {
                val identity = registeredNr.cellIdentity as android.telephony.CellIdentityNr
                val signal = registeredNr.cellSignalStrength as android.telephony.CellSignalStrengthNr
                val rawSinr = signal.ssSinr
                return mapOf(
                    "cellAvailable" to true,
                    "radioTech" to "5G NR",
                    "cellId" to identity.nci.takeIf { it != Long.MAX_VALUE && it >= 0L },
                    "pci" to identity.pci.takeIf { it in 0..1007 },
                    "tac" to identity.tac.takeIf { it != Int.MAX_VALUE && it >= 0 },
                    "arfcn" to identity.nrarfcn.takeIf { it != Int.MAX_VALUE && it >= 0 },
                    "band" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) bandLabel(identity.bands) else null,
                    "rssi" to null,
                    "rsrp" to signal.ssRsrp.takeIf { it in -156..-31 },
                    "rsrq" to signal.ssRsrq.takeIf { it in -43..20 },
                    "sinr" to rawSinr.takeIf { it != Int.MAX_VALUE && it in -23..40 }?.toDouble(),
                    "enbId" to null,
                    "carrier" to telephonyManager.networkOperatorName,
                    "networkType" to networkTypeLabel(telephonyManager, subscriptionId)
                )
            }
        }

        val registeredLte = cells.filterIsInstance<CellInfoLte>()
            .firstOrNull { it.isRegistered }
        if (registeredLte != null) {
            val identity = registeredLte.cellIdentity
            val signal = registeredLte.cellSignalStrength
            val ci = identity.ci.takeIf { it != Int.MAX_VALUE && it in 0..268435455 }
            // Android's CellSignalStrengthLte.getRssnr() is already expressed in dB.
            // Do not divide by 10: the documented LTE range is -20..+30 dB.
            val rawRssnr = signal.rssnr
            val sinrDb = rawRssnr.takeIf { it != Int.MAX_VALUE && it in -20..30 }?.toDouble()
            val rssi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                signal.rssi.takeIf { it != Int.MAX_VALUE && it in -113..-51 }
            } else {
                null
            }
            val bands = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                bandLabel(identity.bands)
            } else {
                null
            }

            return mapOf(
                "cellAvailable" to true,
                "radioTech" to "4G LTE",
                "earfcn" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    identity.earfcn.takeIf { it != Int.MAX_VALUE && it >= 0 }
                } else {
                    null
                },
                "cellId" to ci,
                "enbId" to ci?.let { it shr 8 },
                "pci" to identity.pci.takeIf { it in 0..503 },
                "tac" to identity.tac.takeIf { it != Int.MAX_VALUE && it >= 0 },
                "band" to bands,
                "rssi" to rssi,
                "rsrp" to signal.rsrp.takeIf { it in -160..-20 },
                "rsrq" to signal.rsrq.takeIf { it in -50..0 },
                "sinr" to sinrDb,
                "carrier" to telephonyManager.networkOperatorName,
                "networkType" to networkTypeLabel(telephonyManager, subscriptionId)
            )
        }

        return mapOf(
            "cellAvailable" to false,
            "carrier" to telephonyManager.networkOperatorName,
            "networkType" to networkTypeLabel(telephonyManager, subscriptionId)
        )
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "showNetworkNotification" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success("permission_required")
                            return@setMethodCallHandler
                        }

                        val title = call.argument<String>("title")
                            ?.take(100) ?: "Network monitor"
                        val body = call.argument<String>("body")
                            ?.take(1000) ?: "Network status changed"
                        val notificationId = call.argument<Int>("id") ?: 7301

                        val manager =
                            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val channel = NotificationChannel(
                                "network_alerts",
                                "Network alerts",
                                NotificationManager.IMPORTANCE_DEFAULT
                            )
                            manager.createNotificationChannel(channel)
                        }

                        val openIntent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                PendingIntent.FLAG_IMMUTABLE
                            } else {
                                0
                            }
                        val pendingIntent = PendingIntent.getActivity(
                            this,
                            7301,
                            openIntent,
                            pendingFlags
                        )

                        val notification = NotificationCompat.Builder(this, "network_alerts")
                            .setSmallIcon(android.R.drawable.stat_notify_more)
                            .setContentTitle(title)
                            .setContentText(body)
                            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                            .setContentIntent(pendingIntent)
                            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                            .setAutoCancel(true)
                            .build()

                        NotificationManagerCompat.from(this).notify(notificationId, notification)
                        result.success("shown")
                    } catch (e: SecurityException) {
                        result.success("permission_required")
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }

                "scanWifiNetworks" -> {
                    try {
                        val wifiManager =
                            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        if (!wifiManager.isWifiEnabled) {
                            result.success(
                                mapOf(
                                    "wifiEnabled" to false,
                                    "scanRequested" to false,
                                    "networks" to emptyList<Map<String, Any?>>()
                                )
                            )
                            return@setMethodCallHandler
                        }

                        val scanRequested = wifiManager.startScan()
                        Handler(Looper.getMainLooper()).postDelayed({
                            try {
                                val networks = wifiManager.scanResults.orEmpty()
                                    .map { scan ->
                                        mapOf(
                                            "ssid" to scan.SSID.orEmpty().ifBlank { "Hidden network" },
                                            "frequencyMhz" to scan.frequency,
                                            "channel" to wifiChannel(scan.frequency),
                                            "band" to wifiBand(scan.frequency),
                                            "levelDbm" to scan.level,
                                            "capabilities" to scan.capabilities.orEmpty()
                                        )
                                    }
                                    .sortedByDescending { (it["levelDbm"] as? Int) ?: -127 }

                                result.success(
                                    mapOf(
                                        "wifiEnabled" to true,
                                        "scanRequested" to scanRequested,
                                        "networks" to networks
                                    )
                                )
                            } catch (e: SecurityException) {
                                result.error("WIFI_PERMISSION_DENIED", "Location permission is required for Wi-Fi scan results", null)
                            } catch (e: Exception) {
                                result.error("WIFI_SCAN_ERROR", e.message, null)
                            }
                        }, 3000L)
                    } catch (e: SecurityException) {
                        result.error("WIFI_PERMISSION_DENIED", "Wi-Fi scan permission is required", null)
                    } catch (e: Exception) {
                        result.error("WIFI_SCAN_ERROR", e.message, null)
                    }
                }

                "getCellData" -> {
                    try {
                        startDisplayInfoListeners()
                        val telephonyManager =
                            getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                        val subscriptionManager =
                            getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                        val activeDataSubscriptionId = if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                        ) {
                            SubscriptionManager.getActiveDataSubscriptionId()
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            SubscriptionManager.getDefaultDataSubscriptionId()
                        } else {
                            SubscriptionManager.INVALID_SUBSCRIPTION_ID
                        }
                        result.success(cellSnapshot(telephonyManager, activeDataSubscriptionId))
                    } catch (e: SecurityException) {
                        result.error("PERMISSION_DENIED", "Phone permission is required", null)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }

                "getNeighborCells" -> {
                    try {
                        val telephonyManager =
                            getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                        val cellInfoList = telephonyManager.allCellInfo.orEmpty()

                        val lteCells = cellInfoList
                            .filterIsInstance<CellInfoLte>()
                            .map { cellInfo ->
                                val identity = cellInfo.cellIdentity
                                val signal = cellInfo.cellSignalStrength
                                // Android returns LTE RSSNR directly in dB (range -20..+30).
                                val rawRssnr = signal.rssnr
                                val sinrDb: Double? =
                                    rawRssnr.takeIf { it != Int.MAX_VALUE && it in -20..30 }?.toDouble()

                                mapOf(
                                    "registered" to cellInfo.isRegistered,
                                    "pci" to identity.pci.takeIf { it in 0..503 },
                                    "earfcn" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                        identity.earfcn.takeIf { it != Int.MAX_VALUE && it >= 0 }
                                    } else {
                                        null
                                    },
                                    "cellId" to identity.ci.takeIf { it != Int.MAX_VALUE && it >= 0 },
                                    "tac" to identity.tac.takeIf { it != Int.MAX_VALUE && it >= 0 },
                                    "rsrp" to signal.rsrp.takeIf { it in -160..-20 },
                                    "rsrq" to signal.rsrq.takeIf { it in -50..0 },
                                    "rssi" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                        signal.rssi.takeIf { it != Int.MAX_VALUE && it in -113..-51 }
                                    } else {
                                        null
                                    },
                                    "band" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                        bandLabel(identity.bands)
                                    } else {
                                        null
                                    },
                                    "enbId" to identity.ci.takeIf { it != Int.MAX_VALUE && it in 0..268435455 }?.shr(8),
                                    "sinr" to sinrDb
                                )
                            }
                            .sortedByDescending { it["registered"] == true }

                        val nrCells = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            cellInfoList.filterIsInstance<CellInfoNr>().map { cellInfo ->
                                val identity = cellInfo.cellIdentity as android.telephony.CellIdentityNr
                                val signal = cellInfo.cellSignalStrength as android.telephony.CellSignalStrengthNr
                                val rawSinr = signal.ssSinr
                                mapOf(
                                    "radioTech" to "5G NR",
                                    "registered" to cellInfo.isRegistered,
                                    "pci" to identity.pci.takeIf { it in 0..1007 },
                                    "arfcn" to identity.nrarfcn.takeIf { it != Int.MAX_VALUE && it >= 0 },
                                    "cellId" to identity.nci.takeIf { it != Long.MAX_VALUE },
                                    "tac" to identity.tac.takeIf { it != Int.MAX_VALUE && it >= 0 },
                                    "rsrp" to signal.ssRsrp.takeIf { it in -156..-31 },
                                    "rsrq" to signal.ssRsrq.takeIf { it in -43..20 },
                                    "rssi" to null,
                                    "band" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) bandLabel(identity.bands) else null,
                                    "enbId" to null,
                                    "sinr" to rawSinr.takeIf { it != Int.MAX_VALUE && it in -23..40 }?.toDouble()
                                )
                            }
                        } else {
                            emptyList()
                        }
                        result.success(lteCells + nrCells)
                    } catch (e: SecurityException) {
                        result.error("PERMISSION_DENIED", "Location/phone permission is required", null)
                    } catch (e: Exception) {
                        result.error("NEIGHBOR_CELLS_ERROR", e.message, null)
                    }
                }

                "getSimCards" -> {
                    try {
                        val baseManager =
                            getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                        val subscriptionManager =
                            getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
                        val activeSubscriptions = if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1
                        ) {
                            subscriptionManager.activeSubscriptionInfoList.orEmpty()
                        } else {
                            emptyList()
                        }

                        val cards = activeSubscriptions.map { subscription ->
                            val perSimManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                baseManager.createForSubscriptionId(subscription.subscriptionId)
                            } else {
                                baseManager
                            }
                            val snapshot = cellSnapshot(perSimManager, subscription.subscriptionId)
                            val card = mutableMapOf<String, Any?>(
                                "slot" to (subscription.simSlotIndex + 1),
                                "displayName" to subscription.displayName?.toString(),
                                "carrier" to perSimManager.networkOperatorName
                            )
                            card.putAll(snapshot)
                            card
                        }

                        if (cards.isEmpty()) {
                            result.success(
                                listOf(
                                    mapOf(
                                        "slot" to 1,
                                        "displayName" to "SIM 1",
                                        "carrier" to baseManager.networkOperatorName
                                    ) + cellSnapshot(baseManager, if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) SubscriptionManager.getDefaultDataSubscriptionId() else SubscriptionManager.INVALID_SUBSCRIPTION_ID)
                                )
                            )
                        } else {
                            result.success(cards.sortedBy { (it["slot"] as? Int) ?: 99 })
                        }
                    } catch (e: SecurityException) {
                        result.error("PERMISSION_DENIED", "Phone permission is required to read SIM information", null)
                    } catch (e: Exception) {
                        result.error("SIM_INFO_ERROR", e.message, null)
                    }
                }

                "shareCsv" -> {
                    try {
                        val content = call.argument<String>("content")
                        if (content.isNullOrBlank()) {
                            result.error("EMPTY_EXPORT", "CSV content is empty", null)
                            return@setMethodCallHandler
                        }
                        if (content.length > 5_000_000) {
                            result.error("EXPORT_TOO_LARGE", "CSV export exceeds the supported size", null)
                            return@setMethodCallHandler
                        }
                        if (content.contains('\u0000')) {
                            result.error("INVALID_EXPORT", "CSV contains invalid null characters", null)
                            return@setMethodCallHandler
                        }

                        val exportDirectory = File(cacheDir, "exports")
                        if (!exportDirectory.exists() && !exportDirectory.mkdirs()) {
                            result.error("EXPORT_STORAGE", "Could not create export directory", null)
                            return@setMethodCallHandler
                        }
                        val exportFile = File(exportDirectory, "iraq-network-monitor.csv")
                        // UTF-8 BOM helps spreadsheet apps open Arabic text correctly.
                        exportFile.writeText("\uFEFF$content", Charsets.UTF_8)

                        val exportUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.ota_update_provider",
                            exportFile
                        )
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/csv"
                            putExtra(Intent.EXTRA_STREAM, exportUri)
                            putExtra(Intent.EXTRA_SUBJECT, "IRAQ NETWORK MONITOR - CSV")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = android.content.ClipData.newRawUri("CSV export", exportUri)
                        }
                        startActivity(Intent.createChooser(sendIntent, "Export network measurements as CSV"))
                        result.success("share_opened")
                    } catch (e: Exception) {
                        result.error("CSV_EXPORT_ERROR", e.message, null)
                    }
                }

                "shareKml" -> {
                    try {
                        val content = call.argument<String>("content")
                        if (content.isNullOrBlank()) {
                            result.error("EMPTY_EXPORT", "KML content is empty", null)
                            return@setMethodCallHandler
                        }
                        if (!content.trimStart().startsWith("<?xml") ||
                            !content.contains("<kml")
                        ) {
                            result.error("INVALID_EXPORT", "KML document is invalid", null)
                            return@setMethodCallHandler
                        }

                        val exportDirectory = File(cacheDir, "exports")
                        if (!exportDirectory.exists() && !exportDirectory.mkdirs()) {
                            result.error("EXPORT_STORAGE", "Could not create export directory", null)
                            return@setMethodCallHandler
                        }
                        val exportFile = File(exportDirectory, "iraq-network-monitor.kml")
                        exportFile.writeText(content, Charsets.UTF_8)

                        val exportUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.ota_update_provider",
                            exportFile
                        )
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "application/vnd.google-earth.kml+xml"
                            putExtra(Intent.EXTRA_STREAM, exportUri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = android.content.ClipData.newRawUri("KML export", exportUri)
                        }
                        startActivity(Intent.createChooser(sendIntent, "Export network measurements"))
                        result.success("share_opened")
                    } catch (e: Exception) {
                        result.error("EXPORT_ERROR", e.message, null)
                    }
                }

                "installUpdateApk" -> {
                    try {
                        val path = call.argument<String>("path")

                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is empty", null)
                            return@setMethodCallHandler
                        }

                        val privateFilesDirectory = filesDir.canonicalFile
                        val apkFile = File(path).canonicalFile

                        // path_provider stores application-support files inside
                        // this app's private files directory (never external storage).
                        if (!apkFile.isFile ||
                            !apkFile.path.startsWith(
                                privateFilesDirectory.path + File.separator
                            )
                        ) {
                            result.error(
                                "INVALID_APK",
                                "APK file is missing or outside updates directory",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            val settingsIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )

                            startActivity(settingsIntent)
                            result.success("permission_required")
                            return@setMethodCallHandler
                        }

                        // Validate the downloaded APK before handing it to Android.
                        val archiveInfo = packageManager.getPackageArchiveInfo(
                            apkFile.absolutePath,
                            PackageManager.GET_META_DATA
                        )
                        if (archiveInfo == null) {
                            result.error("INVALID_APK", "Android could not read the downloaded APK", null)
                            return@setMethodCallHandler
                        }
                        if (archiveInfo.packageName != packageName) {
                            result.error(
                                "PACKAGE_MISMATCH",
                                "Downloaded APK package does not match this app",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val installedInfo = packageManager.getPackageInfo(packageName, 0)
                        val installedVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            installedInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            installedInfo.versionCode.toLong()
                        }
                        val apkVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            archiveInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            archiveInfo.versionCode.toLong()
                        }
                        if (apkVersionCode <= installedVersionCode) {
                            result.error(
                                "VERSION_NOT_NEWER",
                                "Downloaded APK is not newer than the installed version",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val apkUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.ota_update_provider",
                            apkFile
                        )

                        // ACTION_VIEW + content URI is more compatible with OEM installers.
                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(
                                apkUri,
                                "application/vnd.android.package-archive"
                            )
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            clipData = android.content.ClipData.newRawUri("APK update", apkUri)
                        }

                        val installers = packageManager.queryIntentActivities(
                            installIntent,
                            PackageManager.MATCH_DEFAULT_ONLY
                        )
                        if (installers.isEmpty()) {
                            result.error("NO_INSTALLER", "No Android package installer is available", null)
                            return@setMethodCallHandler
                        }

                        for (resolveInfo in installers) {
                            try {
                                grantUriPermission(
                                    resolveInfo.activityInfo.packageName,
                                    apkUri,
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                            } catch (_: Exception) {
                                // Normal intent grant remains active.
                            }
                        }

                        startActivity(installIntent)
                        result.success("installer_opened")
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
