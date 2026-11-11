package com.justakhi.hotspot_monitor

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.concurrent.TimeUnit

data class HotspotInterfaceInfo(
    val active: Boolean,
    val interfaceName: String?,
    val gatewayIp: String?,
    val prefixLength: Int,
    val tetherType: String
)

data class CapabilitySnapshot(
    val usageAccessGranted: Boolean,
    val rootBinaryPresent: Boolean,
    val rootGranted: Boolean,
    val nativeProbeAvailable: Boolean,
    val hotspot: HotspotInterfaceInfo
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "usageAccessGranted" to usageAccessGranted,
        "rootBinaryPresent" to rootBinaryPresent,
        "rootGranted" to rootGranted,
        "nativeProbeAvailable" to nativeProbeAvailable,
        "hotspotActive" to hotspot.active,
        "hotspotInterface" to hotspot.interfaceName,
        "gatewayIp" to hotspot.gatewayIp,
        "prefixLength" to hotspot.prefixLength,
        "tetherType" to hotspot.tetherType
    )
}

data class RootInvocation(
    val suPath: String,
    val mode: String // "dash_c", "mount_master", "uid_sh"
) {
    fun buildArgs(command: String): List<String> = when (mode) {
        "mount_master" -> listOf(suPath, "--mount-master", "-c", command)
        "uid_sh" -> listOf(suPath, "0", "sh", "-c", command)
        else -> listOf(suPath, "-c", command)
    }
}

class CapabilityChecker(private val context: Context) {
    @Volatile
    var rootGrantedCached: Boolean = false
        private set

    @Volatile
    var verifiedInvocation: RootInvocation? = null
        private set

    fun isUsageAccessGranted(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun collectSuCandidates(): List<String> {
        val pathDirs = System.getenv("PATH")
            ?.split(":")
            ?.filter { it.isNotBlank() }
            .orEmpty()

        val candidates = buildList {
            for (dir in pathDirs) {
                add("$dir/su")
            }
            // KernelSU / KernelSU-Next / SukiSU / APatch / Magisk direct locations
            add("/data/adb/ksu/bin/su")
            add("/data/adb/ap/bin/su")
            add("/data/adb/magisk/su")
            add("/data/adb/su/bin/su")
            // Android system / vendor / ramdisk overlays
            add("/product/bin/su")
            add("/system_ext/bin/su")
            add("/vendor/bin/su")
            add("/odm/bin/su")
            add("/system/bin/su")
            add("/system/xbin/su")
            add("/sbin/su")
            add("/debug_ramdisk/su")
            add("/su/bin/su")
            add("/su/xbin/su")
            add("/magisk/.core/bin/su")
        }.distinct().toMutableList()

        // Shell lookup fallback in case SELinux hides directory stat checks on custom ROMs.
        for (probeCmd in listOf(listOf("which", "su"), listOf("sh", "-c", "command -v su"))) {
            try {
                val proc = ProcessBuilder(probeCmd)
                    .redirectErrorStream(true)
                    .start()
                if (proc.waitFor(1, TimeUnit.SECONDS)) {
                    val out = proc.inputStream.bufferedReader().readText().trim()
                    if (proc.exitValue() == 0 && out.isNotBlank() && !out.contains("not found")) {
                        val found = out.lines().firstOrNull()?.trim()
                        if (!found.isNullOrBlank() && !candidates.contains(found)) {
                            candidates.add(found)
                        }
                    }
                } else {
                    proc.destroyForcibly()
                }
            } catch (_: Exception) {
            }
        }

        return candidates.filter {
            try {
                File(it).exists()
            } catch (_: Exception) {
                false
            }
        }
    }

    fun resolveSuExecutable(): String? {
        verifiedInvocation?.suPath?.let { return it }
        return collectSuCandidates().firstOrNull()
    }

    fun buildSuArgs(command: String): List<String> {
        val inv = verifiedInvocation
            ?: RootInvocation(resolveSuExecutable() ?: "su", "dash_c")
        return inv.buildArgs(command)
    }

    fun isRootBinaryPresent(): Boolean {
        if (verifiedInvocation != null || resolveSuExecutable() != null) return true
        val managerMarkers = listOf(
            "/data/adb/magisk",
            "/data/adb/ksu",
            "/data/adb/ksud",
            "/data/adb/ap",
            "/data/adb/apd",
            "/data/adb/supersu",
            "/sbin/.magisk"
        )
        return managerMarkers.any {
            try {
                File(it).exists()
            } catch (_: Exception) {
                false
            }
        }
    }

    fun probeProbeBinary(): File? {
        val dir = context.applicationInfo.nativeLibraryDir ?: return null
        val file = File(dir, "libhs_probe.so")
        return if (file.exists()) file else null
    }

    fun requestRootAccess(): Boolean {
        val candidates = collectSuCandidates().ifEmpty { listOf("su") }
        val modes = listOf("dash_c", "mount_master", "uid_sh")

        for (candidate in candidates) {
            for (mode in modes) {
                val inv = RootInvocation(candidate, mode)
                if (testRootInvocation(inv)) {
                    verifiedInvocation = inv
                    rootGrantedCached = true
                    return true
                }
            }
        }

        rootGrantedCached = false
        return false
    }

    private fun testRootInvocation(inv: RootInvocation): Boolean {
        return try {
            val process = ProcessBuilder(inv.buildArgs("id"))
                .redirectErrorStream(true)
                .start()
            val completed = process.waitFor(8, TimeUnit.SECONDS)
            if (!completed) {
                process.destroyForcibly()
                return false
            }
            val output = process.inputStream.bufferedReader().readText()
            process.exitValue() == 0 && output.contains("uid=0")
        } catch (_: Exception) {
            false
        }
    }

    fun detectHotspotInterface(useRootIfGranted: Boolean = rootGrantedCached): HotspotInterfaceInfo {
        val apEnabledViaWifiManager = isWifiApEnabledReflective()
        val fastResult = detectApFromNetworkInterfaces(apEnabledViaWifiManager)
        if (fastResult.active && !fastResult.interfaceName.isNullOrBlank()) {
            return fastResult
        }

        if (useRootIfGranted) {
            detectApViaRootIw()?.let { return it }
        }

        return fastResult
    }

    fun snapshot(useRoot: Boolean = rootGrantedCached): CapabilitySnapshot {
        val probe = probeProbeBinary()
        return CapabilitySnapshot(
            usageAccessGranted = isUsageAccessGranted(),
            rootBinaryPresent = isRootBinaryPresent(),
            rootGranted = useRoot,
            nativeProbeAvailable = probe != null,
            hotspot = detectHotspotInterface(useRoot)
        )
    }

    private fun isWifiApEnabledReflective(): Boolean {
        return try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return false
            val method = wifiManager.javaClass.getDeclaredMethod("isWifiApEnabled")
            method.isAccessible = true
            (method.invoke(wifiManager) as? Boolean) ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun detectApViaRootIw(): HotspotInterfaceInfo? {
        val suCmd = resolveSuExecutable() ?: "su"
        return try {
            val process = ProcessBuilder(suCmd, "-c", "iw dev")
                .redirectErrorStream(true)
                .start()
            if (!process.waitFor(2, TimeUnit.SECONDS)) {
                process.destroyForcibly()
                return null
            }
            val text = process.inputStream.bufferedReader().readText()
            var currentIface: String? = null
            var apIface: String? = null
            for (rawLine in text.lines()) {
                val line = rawLine.trim()
                if (line.startsWith("Interface ")) {
                    currentIface = line.removePrefix("Interface ").trim()
                } else if (line.startsWith("type ") && line.contains("AP", ignoreCase = true)) {
                    apIface = currentIface
                    break
                }
            }
            if (apIface != null) {
                val addr = findIpv4OnInterface(apIface)
                if (addr != null) {
                    return HotspotInterfaceInfo(
                        active = true,
                        interfaceName = apIface,
                        gatewayIp = addr.first,
                        prefixLength = addr.second,
                        tetherType = "wifi_ap"
                    )
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun findIpv4OnInterface(ifaceName: String): Pair<String, Int>? {
        val iface = NetworkInterface.getByName(ifaceName) ?: return null
        if (!iface.isUp) return null
        for (ifAddr in iface.interfaceAddresses) {
            val addr = ifAddr.address
            if (addr is Inet4Address && !addr.isLoopbackAddress && isPrivateRfc1918(addr.hostAddress ?: "")) {
                return (addr.hostAddress ?: "") to ifAddr.networkPrefixLength.toInt().coerceIn(8, 30)
            }
        }
        return null
    }

    private fun detectApFromNetworkInterfaces(wifiApReportedActive: Boolean): HotspotInterfaceInfo {
        val priorityPrefixes = listOf("ap", "swlan", "softap", "wlan1", "wlan2", "rndis", "usb", "ncm", "bt-pan")
        val excludedPrefixes = listOf("lo", "rmnet", "ccmni", "tun", "tap", "ppp", "dummy", "v4-", "sit", "ip6")

        data class Candidate(
            val name: String,
            val ip: String,
            val prefix: Int,
            val score: Int,
            val tetherType: String
        )

        val candidates = mutableListOf<Candidate>()
        val interfaces = try {
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        } catch (_: Exception) {
            emptyList()
        }

        for (iface in interfaces) {
            val name = iface.name ?: continue
            if (!iface.isUp || iface.isLoopback) continue
            if (excludedPrefixes.any { name.startsWith(it, ignoreCase = true) }) continue

            for (ifAddr in iface.interfaceAddresses) {
                val addr = ifAddr.address
                if (addr !is Inet4Address || addr.isLoopbackAddress) continue
                val ip = addr.hostAddress ?: continue
                if (!isPrivateRfc1918(ip)) continue

                val prefix = ifAddr.networkPrefixLength.toInt().coerceIn(8, 30)
                val isUsb = name.startsWith("rndis") || name.startsWith("usb") || name.startsWith("ncm")
                val isDedicatedAp = name.startsWith("ap") || name.startsWith("swlan") || name.startsWith("softap") ||
                    name == "wlan1" || name == "wlan2"

                val score = when {
                    isDedicatedAp -> 100
                    isUsb -> 90
                    name == "wlan0" && wifiApReportedActive -> 85
                    priorityPrefixes.any { name.startsWith(it) } -> 70
                    ip.startsWith("192.168.43.") || ip.startsWith("192.168.137.") -> 65
                    else -> 10
                }
                if (score >= 60) {
                    candidates.add(
                        Candidate(
                            name = name,
                            ip = ip,
                            prefix = prefix,
                            score = score,
                            tetherType = if (isUsb) "usb" else "wifi_ap"
                        )
                    )
                }
            }
        }

        val best = candidates.maxByOrNull { it.score }
        if (best != null) {
            return HotspotInterfaceInfo(
                active = true,
                interfaceName = best.name,
                gatewayIp = best.ip,
                prefixLength = best.prefix,
                tetherType = best.tetherType
            )
        }

        return HotspotInterfaceInfo(
            active = wifiApReportedActive,
            interfaceName = null,
            gatewayIp = null,
            prefixLength = 24,
            tetherType = if (wifiApReportedActive) "wifi_ap" else "none"
        )
    }

    private fun isPrivateRfc1918(ip: String): Boolean {
        val parts = ip.split(".").mapNotNull { it.toIntOrNull() }
        if (parts.size != 4) return false
        return when {
            parts[0] == 10 -> true
            parts[0] == 172 && parts[1] in 16..31 -> true
            parts[0] == 192 && parts[1] == 168 -> true
            else -> false
        }
    }
}
