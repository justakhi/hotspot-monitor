package com.justakhi.hotspot_monitor

import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

data class RootClientMeta(
    val id: String,
    val ip: String,
    val mac: String?,
    val hostname: String?,
    val vendor: String,
    val isRandomizedMac: Boolean,
    val neighborState: String,
    val rssiDbm: Int?,
    val txBitrateMbps: Double?,
    val rxBitrateMbps: Double?,
    val isOnline: Boolean,
    val lastSeenMs: Long
)

data class EndpointUsageAcc(
    val endpoint: String,
    var downloadBytes: Long = 0L,
    var uploadBytes: Long = 0L,
    var lastActiveMs: Long = 0L
) {
    fun toMap(): Map<String, Any> = mapOf(
        "endpoint" to endpoint,
        "downloadBytes" to downloadBytes,
        "uploadBytes" to uploadBytes,
        "lastActiveMs" to lastActiveMs
    )
}

data class ServiceUsageAcc(
    val serviceId: String,
    val displayName: String,
    val category: String,
    var downloadBytes: Long = 0L,
    var uploadBytes: Long = 0L,
    val domains: LinkedHashSet<String> = linkedSetOf(),
    val endpoints: ConcurrentHashMap<String, EndpointUsageAcc> = ConcurrentHashMap(),
    var lastActiveMs: Long = 0L
) {
    fun toMap(): Map<String, Any> = mapOf(
        "serviceId" to serviceId,
        "displayName" to displayName,
        "category" to category,
        "downloadBytes" to downloadBytes,
        "uploadBytes" to uploadBytes,
        "topDomains" to domains.take(5),
        "endpoints" to endpoints.values
            .sortedByDescending { it.downloadBytes + it.uploadBytes }
            .take(15)
            .map { it.toMap() },
        "lastActiveMs" to lastActiveMs
    )
}

data class DeviceTrafficAcc(
    val id: String,
    var ip: String,
    var downloadBytes: Long = 0L,
    var uploadBytes: Long = 0L,
    var currentDownloadBps: Long = 0L,
    var currentUploadBps: Long = 0L,
    var pendingRxBytes: Long = 0L,
    var pendingTxBytes: Long = 0L,
    var lastTrafficMs: Long = 0L,
    val services: ConcurrentHashMap<String, ServiceUsageAcc> = ConcurrentHashMap()
)

class RootTelemetrySource {
    private data class LearnedHostEntry(
        val host: String,
        val updatedAtMs: Long
    )

    companion object {
        private const val LEARNED_CACHE_FILE = "learned_hosts_v1.tsv"
        private const val CLIENT_HOST_TTL_MS = 6L * 3600L * 1000L
        private const val SHARED_HOST_TTL_MS = 3L * 3600L * 1000L
        private const val MAX_LEARNED_ENTRIES = 1500
    }

    private val clientsById = ConcurrentHashMap<String, RootClientMeta>()
    private val trafficById = ConcurrentHashMap<String, DeviceTrafficAcc>()
    private val ipToMac = ConcurrentHashMap<String, String>()
    private val dhcpHostByMac = ConcurrentHashMap<String, String>()
    private val dhcpHostByIp = ConcurrentHashMap<String, String>()
    private val dhcpIpByMac = ConcurrentHashMap<String, String>()
    private val osHintByMac = ConcurrentHashMap<String, String>()
    private val ptrByRemoteIp = ConcurrentHashMap<String, String>()
    private val ptrPending = ConcurrentHashMap.newKeySet<String>()
    private val learnedHostByClientIpPort = ConcurrentHashMap<String, LearnedHostEntry>()
    private val learnedHostByIpPort = ConcurrentHashMap<String, LearnedHostEntry>()
    private val learnedHostByIp = ConcurrentHashMap<String, LearnedHostEntry>()
    private val ptrExecutor = Executors.newFixedThreadPool(4)
    private val running = AtomicBoolean(false)
    private val persistDirty = AtomicBoolean(false)

    @Volatile
    private var learnedCacheFile: File? = null

    @Volatile
    private var lastCachePersistMs = 0L

    @Volatile
    private var lastNetworkStackScanMs = 0L

    @Volatile
    var suCommand: String = "su"

    @Volatile
    var suArgsBuilder: ((String) -> List<String>)? = null

    @Volatile
    private var probeProcess: Process? = null
    private var probeThread: Thread? = null

    @Volatile
    var probeActive: Boolean = false
        private set

    @Volatile
    var probeError: String? = null
        private set

    fun initStorage(appFilesDir: File) {
        val file = File(appFilesDir, LEARNED_CACHE_FILE)
        learnedCacheFile = file
        if (!file.exists()) return
        val cutoff = System.currentTimeMillis() - CLIENT_HOST_TTL_MS
        try {
            file.forEachLine { raw ->
                val parts = raw.split('\t')
                if (parts.size < 4) return@forEachLine
                val kind = parts[0]
                val key = parts[1]
                val host = parts[2]
                val ts = parts[3].toLongOrNull() ?: return@forEachLine
                if (host.isBlank() || ts < cutoff) return@forEachLine
                val entry = LearnedHostEntry(host, ts)
                when (kind) {
                    "C" -> learnedHostByClientIpPort[key] = entry
                    "P" -> learnedHostByIpPort[key] = entry
                    "I" -> learnedHostByIp[key] = entry
                }
            }
        } catch (_: Exception) {
        }
    }

    fun startProbe(
        probeBinary: File?,
        iface: String,
        gatewayIp: String,
        prefixLength: Int
    ) {
        stopProbe()
        if (probeBinary == null || !probeBinary.exists()) {
            probeActive = false
            probeError = "Native probe binary not found"
            return
        }

        running.set(true)
        probeError = null
        probeThread = Thread({
            try {
                val cmd = "${probeBinary.absolutePath} $iface $gatewayIp $prefixLength"
                val args = suArgsBuilder?.invoke(cmd) ?: listOf(suCommand, "-c", cmd)
                val proc = ProcessBuilder(args)
                    .redirectErrorStream(false)
                    .start()
                probeProcess = proc

                val errThread = Thread({
                    try {
                        BufferedReader(InputStreamReader(proc.errorStream)).use { errReader ->
                            val sb = StringBuilder()
                            var line: String?
                            while (errReader.readLine().also { line = it } != null) {
                                if (sb.length < 512) {
                                    sb.append(line).append(' ')
                                }
                            }
                            if (sb.isNotBlank()) {
                                probeError = sb.toString().trim()
                            }
                        }
                    } catch (_: Exception) {
                    }
                }, "HsProbeErr").apply {
                    isDaemon = true
                    start()
                }

                BufferedReader(InputStreamReader(proc.inputStream)).use { reader ->
                    while (running.get()) {
                        val raw = reader.readLine() ?: break
                        if (raw.startsWith("READY\t")) {
                            probeActive = true
                            probeError = null
                        } else if (raw.startsWith("D\t")) {
                            handleProbeDataLine(raw)
                        } else if (raw.startsWith("H\t")) {
                            handleDhcpIdentityLine(raw)
                        } else if (raw.startsWith("F\t")) {
                            finalizeSecondSpeeds()
                        }
                    }
                }

                errThread.join(300)
            } catch (e: Exception) {
                if (running.get()) {
                    probeError = e.message ?: "Probe execution failed"
                }
            } finally {
                probeActive = false
                running.set(false)
            }
        }, "HsProbeReader").apply {
            isDaemon = true
            start()
        }
    }

    fun stopProbe() {
        running.set(false)
        probeActive = false
        val proc = probeProcess
        probeProcess = null
        if (proc != null) {
            try {
                proc.outputStream.close()
            } catch (_: Exception) {
            }
            try {
                if (!proc.waitFor(400, TimeUnit.MILLISECONDS)) {
                    proc.destroy()
                    if (!proc.waitFor(300, TimeUnit.MILLISECONDS)) {
                        proc.destroyForcibly()
                    }
                }
            } catch (_: Exception) {
                try {
                    proc.destroyForcibly()
                } catch (_: Exception) {
                }
            }
        }
        probeThread?.interrupt()
        probeThread = null
        persistLearnedHosts(force = true)
    }

    fun resetSession() {
        trafficById.clear()
        clientsById.clear()
        ipToMac.clear()
    }

    fun refreshClients(
        iface: String?,
        gatewayIp: String?,
        discoveredHostnames: Map<String, String> = emptyMap()
    ): List<Map<String, Any?>> {
        val now = System.currentTimeMillis()
        val subnetPrefix = gatewayIp?.substringBeforeLast('.')

        val needsDhcpRefresh = dhcpHostByMac.isEmpty() ||
            clientsById.values.any { it.hostname.isNullOrBlank() } ||
            (now - lastNetworkStackScanMs) >= 15_000L
        if (needsDhcpRefresh && (now - lastNetworkStackScanMs) >= 4_000L) {
            lastNetworkStackScanMs = now
            refreshDhcpRepositoryFromNetworkStack()
        }

        val script = buildString {
            if (!iface.isNullOrBlank()) {
                append("echo '---APMAC---'; cat /sys/class/net/$iface/address 2>/dev/null; ")
                append("echo '---NEIGH---'; ip -4 neigh show dev $iface 2>/dev/null || ip -4 neigh show 2>/dev/null; ")
                append("echo '---NEIGH6---'; ip -6 neigh show dev $iface 2>/dev/null; ")
                append("echo '---IW---'; iw dev $iface station dump 2>/dev/null; ")
            } else {
                append("echo '---NEIGH---'; ip -4 neigh show 2>/dev/null; ")
            }
            append("echo '---ARP---'; cat /proc/net/arp 2>/dev/null; ")
            append("echo '---LEASES---'; ")
            append("cat /data/misc/apexdata/com.android.tethering/misc/dhcp/dnsmasq.leases ")
            append("/data/misc/dhcp/dnsmasq.leases ")
            append("/data/misc/tethering/dnsmasq.leases ")
            append("/data/misc/dhcp/dhcpcd-*.leases 2>/dev/null")
        }

        val output = runSuCommand(script, 3) ?: ""
        val sections = parseSections(output)

        val apMac = sections["APMAC"].orEmpty()
            .firstOrNull { it.trim().contains(":") }
            ?.trim()
            ?.uppercase()

        val leasesByMac = mutableMapOf<String, String>()
        val leasesByIp = mutableMapOf<String, String>()
        for (line in sections["LEASES"].orEmpty()) {
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size >= 4 && parts[1].contains(":") && parts[2].contains(".")) {
                val mac = parts[1].uppercase()
                val ip = parts[2]
                val host = parts[3]
                if (host != "*" && host.isNotBlank()) {
                    leasesByMac[mac] = host
                    leasesByIp[ip] = host
                }
            }
        }

        val stationByMac = parseIwStations(sections["IW"].orEmpty())
            .filterKeys { apMac == null || it != apMac }
        val seenIds = mutableSetOf<String>()
        val staleV4Ids = mutableSetOf<String>()

        for (line in sections["NEIGH"].orEmpty()) {
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.isEmpty()) continue
            val ip = parts[0]
            if (!ip.contains(".") || ip == gatewayIp) continue
            if (subnetPrefix != null && !ip.startsWith("$subnetPrefix.")) continue

            val lladdrIdx = parts.indexOf("lladdr")
            val mac = if (lladdrIdx >= 0 && lladdrIdx + 1 < parts.size) {
                parts[lladdrIdx + 1].uppercase()
            } else {
                null
            }
            val state = parts.lastOrNull()?.uppercase() ?: "UNKNOWN"
            if (state == "FAILED" || state == "INCOMPLETE") continue

            val id = mac ?: ip
            if (mac != null) ipToMac[ip] = mac

            if (state == "STALE") {
                // Poke kernel ARP state machine so truly connected sleeping phones reply REACHABLE
                // while disconnected phones quickly transition to FAILED and leave Connected Devices.
                pokeUdpDiscardAsync(ip)
            }

            val lastTraffic = trafficById[id]?.lastTrafficMs ?: 0L
            val ipv4Alive = state == "REACHABLE" ||
                state == "DELAY" ||
                state == "PROBE" ||
                state == "PERMANENT" ||
                (stationByMac.containsKey(mac)) ||
                (now - lastTraffic) < 12_000L

            if (ipv4Alive) {
                seenIds.add(id)
            } else {
                staleV4Ids.add(id)
            }
            upsertClientMeta(
                id = id,
                ip = ip,
                mac = mac,
                state = state,
                leasesByMac = leasesByMac,
                leasesByIp = leasesByIp,
                stationByMac = stationByMac,
                now = now
            )
        }

        for (line in sections["NEIGH6"].orEmpty()) {
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.isEmpty()) continue
            val ip6 = parts[0]
            if (!ip6.contains(":")) continue
            val lladdrIdx = parts.indexOf("lladdr")
            if (lladdrIdx < 0 || lladdrIdx + 1 >= parts.size) continue
            val mac = parts[lladdrIdx + 1].uppercase()
            if (apMac != null && mac == apMac) continue
            val state = parts.lastOrNull()?.uppercase() ?: "UNKNOWN"
            if (state == "FAILED" || state == "INCOMPLETE") continue

            val v6Alive = state == "REACHABLE" ||
                state == "DELAY" ||
                state == "PROBE" ||
                state == "PERMANENT" ||
                stationByMac.containsKey(mac)
            if (v6Alive) {
                seenIds.add(mac)
            }

            val existing = clientsById[mac]
            val shouldReplaceIp = existing == null ||
                (!existing.ip.contains(".") && existing.ip.startsWith("fe80:") && !ip6.startsWith("fe80:"))
            if (shouldReplaceIp || v6Alive) {
                upsertClientMeta(
                    id = mac,
                    ip = if (existing?.ip?.contains(".") == true) existing.ip else ip6,
                    mac = mac,
                    state = state,
                    leasesByMac = leasesByMac,
                    leasesByIp = leasesByIp,
                    stationByMac = stationByMac,
                    now = now
                )
            }
        }

        for (line in sections["ARP"].orEmpty()) {
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size < 6 || parts[0] == "IP") continue
            val ip = parts[0]
            if (ip == gatewayIp) continue
            if (subnetPrefix != null && !ip.startsWith("$subnetPrefix.")) continue
            val mac = parts[3].uppercase()
            if (mac == "00:00:00:00:00:00") continue
            val flags = parts[2]
            if (flags == "0x0") continue

            ipToMac[ip] = mac
            if (seenIds.contains(mac) || staleV4Ids.contains(mac)) continue
            if (seenIds.isNotEmpty() || sections["NEIGH"].orEmpty().isNotEmpty()) {
                // Only fall back to /proc/net/arp when NEIGH wasn't authoritative, or trigger ARP check.
                pokeUdpDiscardAsync(ip)
            }
            seenIds.add(mac)
            upsertClientMeta(
                id = mac,
                ip = ip,
                mac = mac,
                state = "ARP",
                leasesByMac = leasesByMac,
                leasesByIp = leasesByIp,
                stationByMac = stationByMac,
                now = now
            )
        }

        for ((id, traffic) in trafficById) {
            if (!seenIds.contains(id) && !clientsById.containsKey(id)) {
                val mac = if (id.contains(":")) id else null
                val vendorInfo = OuiVendorLookup.lookup(mac)
                val osHint = if (mac != null) osHintByMac[mac] else null
                val vendor = if (vendorInfo.vendor == "Unknown" || vendorInfo.vendor.startsWith("Unknown (") || vendorInfo.isRandomized) {
                    osHint ?: vendorInfo.vendor
                } else {
                    vendorInfo.vendor
                }
                clientsById[id] = RootClientMeta(
                    id = id,
                    ip = traffic.ip,
                    mac = mac,
                    hostname = (if (mac != null) dhcpHostByMac[mac] else null)
                        ?: dhcpHostByIp[traffic.ip]
                        ?: discoveredHostnames[traffic.ip]
                        ?: leasesByMac[id]
                        ?: leasesByIp[traffic.ip],
                    vendor = vendor,
                    isRandomizedMac = vendorInfo.isRandomized,
                    neighborState = "ACTIVE",
                    rssiDbm = null,
                    txBitrateMbps = null,
                    rxBitrateMbps = null,
                    isOnline = true,
                    lastSeenMs = now
                )
            }
        }

        if (discoveredHostnames.isNotEmpty() || dhcpHostByMac.isNotEmpty() || dhcpHostByIp.isNotEmpty() || osHintByMac.isNotEmpty()) {
            for ((id, existing) in clientsById) {
                val mac = existing.mac
                val bestHost = (if (mac != null) dhcpHostByMac[mac] else null)
                    ?: dhcpHostByIp[existing.ip]
                    ?: discoveredHostnames[existing.ip]
                    ?: existing.hostname
                val preferredIpv4 = if (!existing.ip.contains(".") && mac != null) {
                    dhcpIpByMac[mac]
                } else {
                    null
                }
                val bestIp = preferredIpv4 ?: existing.ip
                val osHint = if (mac != null) osHintByMac[mac] else null
                val bestVendor = if ((existing.vendor == "Unknown" || existing.vendor.startsWith("Unknown (") || existing.isRandomizedMac) && osHint != null) {
                    osHint
                } else {
                    existing.vendor
                }
                if (bestHost != existing.hostname || bestVendor != existing.vendor || bestIp != existing.ip) {
                    clientsById[id] = existing.copy(
                        ip = bestIp,
                        hostname = bestHost,
                        vendor = bestVendor
                    )
                }
            }
        }

        for ((id, existing) in clientsById) {
            if (!seenIds.contains(id)) {
                val lastTraffic = trafficById[id]?.lastTrafficMs ?: 0L
                val recent = (now - maxOf(existing.lastSeenMs, lastTraffic)) < 10_000L
                if (!recent && existing.isOnline) {
                    clientsById[id] = existing.copy(isOnline = false, neighborState = "OFFLINE")
                }
            }
        }

        return buildDevicePayloadList()
    }

    fun readInterfaceTotals(iface: String?): Pair<Long, Long>? {
        if (iface.isNullOrBlank()) return null
        val out = runSuCommand("cat /proc/net/dev 2>/dev/null", 2) ?: return null
        for (line in out.lines()) {
            val trimmed = line.trim()
            if (!trimmed.startsWith("$iface:")) continue
            val afterColon = trimmed.substringAfter(":").trim()
            val cols = afterColon.split(Regex("\\s+"))
            if (cols.size >= 10) {
                val ifaceRx = cols[0].toLongOrNull() ?: 0L // From client -> upload
                val ifaceTx = cols[8].toLongOrNull() ?: 0L // To client -> download
                return ifaceTx to ifaceRx
            }
        }
        return null
    }

    fun buildDevicePayloadList(): List<Map<String, Any?>> {
        val allIds = (clientsById.keys + trafficById.keys).toSet()
        return allIds.map { id ->
            val meta = clientsById[id]
            val traffic = trafficById[id]
            val services = traffic?.services?.values
                ?.sortedByDescending { it.downloadBytes + it.uploadBytes }
                ?.map { it.toMap() }
                .orEmpty()

            mapOf(
                "id" to id,
                "ip" to (meta?.ip ?: traffic?.ip ?: "0.0.0.0"),
                "mac" to (meta?.mac ?: if (id.contains(":")) id else null),
                "hostname" to meta?.hostname,
                "vendor" to (meta?.vendor ?: "Unknown"),
                "isRandomizedMac" to (meta?.isRandomizedMac ?: false),
                "neighborState" to (meta?.neighborState ?: "UNKNOWN"),
                "rssiDbm" to meta?.rssiDbm,
                "txBitrateMbps" to meta?.txBitrateMbps,
                "rxBitrateMbps" to meta?.rxBitrateMbps,
                "isOnline" to (meta?.isOnline ?: true),
                "lastSeenMs" to (meta?.lastSeenMs ?: traffic?.lastTrafficMs ?: 0L),
                "downloadBytes" to (traffic?.downloadBytes ?: 0L),
                "uploadBytes" to (traffic?.uploadBytes ?: 0L),
                "currentDownloadBps" to (traffic?.currentDownloadBps ?: 0L),
                "currentUploadBps" to (traffic?.currentUploadBps ?: 0L),
                "services" to services
            )
        }.sortedByDescending {
            ((it["downloadBytes"] as? Long) ?: 0L) + ((it["uploadBytes"] as? Long) ?: 0L)
        }
    }

    private fun handleDhcpIdentityLine(line: String) {
        // H\t<mac>\t<hostname>\t<vendor_class>
        val parts = line.split('\t')
        if (parts.size < 4) return
        val mac = parts[1].trim().uppercase()
        if (!mac.contains(":")) return
        val host = parts[2].trim()
        val vendorClass = parts[3].trim()
        if (host.isNotEmpty()) {
            dhcpHostByMac[mac] = host
        }
        if (vendorClass.isNotEmpty()) {
            val lower = vendorClass.lowercase()
            val friendly = when {
                lower.contains("android-dhcp") -> "Android (${vendorClass.substringAfter("android-dhcp-", "").ifEmpty { "Device" }})"
                lower.contains("msft") -> "Windows PC"
                lower.contains("dhcpcd") -> "Linux / Android"
                else -> vendorClass
            }
            osHintByMac[mac] = friendly
        }
    }

    private fun handleProbeDataLine(line: String) {
        // D\t<client_mac>\t<client_ip>\t<host>\t<remote_ip>\t<remote_port>\t<proto>\t<rx_bytes>\t<tx_bytes>
        val parts = line.split('\t')
        if (parts.size < 9) return
        val clientMac = parts[1].uppercase()
        val clientIp = parts[2]
        val host = parts[3]
        val remoteIp = parts[4]
        val remotePort = parts[5].toIntOrNull() ?: 0
        val proto = parts[6].toIntOrNull() ?: 0
        val rxBytes = parts[7].toLongOrNull() ?: 0L
        val txBytes = parts[8].toLongOrNull() ?: 0L
        if (rxBytes == 0L && txBytes == 0L) return

        val id = if (clientMac.contains(":")) clientMac else (ipToMac[clientIp] ?: clientIp)
        if (clientIp.contains(".") && clientMac.contains(":")) {
            ipToMac[clientIp] = clientMac
        }

        val now = System.currentTimeMillis()
        val device = trafficById.getOrPut(id) {
            DeviceTrafficAcc(
                id = id,
                ip = if (clientIp.isNotBlank()) clientIp else (clientsById[id]?.ip ?: "0.0.0.0")
            )
        }
        if (clientIp.contains(".") && !device.ip.contains(".")) {
            device.ip = clientIp
        }
        device.downloadBytes += rxBytes
        device.uploadBytes += txBytes
        device.pendingRxBytes += rxBytes
        device.pendingTxBytes += txBytes
        device.lastTrafficMs = now

        val effectiveHost = if (host.isNotBlank()) {
            learnHost(id, remoteIp, remotePort, host, now)
            host
        } else {
            val learned = resolveLearnedHost(id, remoteIp, remotePort, now)
            if (learned != null) {
                learned
            } else {
                val cachedPtr = ptrByRemoteIp[remoteIp]
                if (cachedPtr == null && remoteIp.isNotBlank()) {
                    enqueuePtrLookup(remoteIp)
                    ""
                } else {
                    cachedPtr ?: ""
                }
            }
        }

        val hostForClassification = if (effectiveHost.startsWith("http://")) {
            effectiveHost.removePrefix("http://").substringBefore("/")
        } else {
            effectiveHost
        }

        val classified = ServiceClassifier.classify(hostForClassification, remoteIp, remotePort, proto)
        val service = device.services.getOrPut(classified.serviceId) {
            ServiceUsageAcc(
                serviceId = classified.serviceId,
                displayName = classified.displayName,
                category = classified.category
            )
        }
        service.downloadBytes += rxBytes
        service.uploadBytes += txBytes
        service.lastActiveMs = now
        val detail = if (effectiveHost.isNotBlank()) effectiveHost else classified.domain
        if (detail.isNotBlank()) {
            if (service.domains.size < 12) {
                service.domains.add(detail)
            }
            if (service.endpoints.size < 30 || service.endpoints.containsKey(detail)) {
                val ep = service.endpoints.getOrPut(detail) {
                    EndpointUsageAcc(endpoint = detail)
                }
                ep.downloadBytes += rxBytes
                ep.uploadBytes += txBytes
                ep.lastActiveMs = now
            }
        }
    }

    private fun learnHost(
        clientId: String,
        remoteIp: String,
        remotePort: Int,
        rawHost: String,
        now: Long
    ) {
        if (remoteIp.isBlank()) return
        val normalized = if (rawHost.startsWith("http://")) {
            rawHost.removePrefix("http://").substringBefore("/")
        } else {
            rawHost
        }.trim().lowercase()
        if (!normalized.contains(".") ||
            normalized.endsWith(".1e100.net") ||
            normalized.endsWith(".in-addr.arpa") ||
            normalized.endsWith(".ip6.arpa")
        ) {
            return
        }

        val entry = LearnedHostEntry(normalized, now)
        learnedHostByClientIpPort["$clientId|$remoteIp|$remotePort"] = entry
        learnedHostByIpPort["$remoteIp|$remotePort"] = entry
        learnedHostByIp[remoteIp] = entry
        persistDirty.set(true)

        if (now - lastCachePersistMs >= 20_000L) {
            lastCachePersistMs = now
            ptrExecutor.submit { persistLearnedHosts(force = false) }
        }
    }

    private fun resolveLearnedHost(
        clientId: String,
        remoteIp: String,
        remotePort: Int,
        now: Long
    ): String? {
        if (remoteIp.isBlank()) return null
        learnedHostByClientIpPort["$clientId|$remoteIp|$remotePort"]?.let { entry ->
            if (now - entry.updatedAtMs <= CLIENT_HOST_TTL_MS) {
                return entry.host
            }
        }
        learnedHostByIpPort["$remoteIp|$remotePort"]?.let { entry ->
            if (now - entry.updatedAtMs <= SHARED_HOST_TTL_MS) {
                return entry.host
            }
        }
        learnedHostByIp[remoteIp]?.let { entry ->
            if (now - entry.updatedAtMs <= SHARED_HOST_TTL_MS) {
                return entry.host
            }
        }
        return null
    }

    private fun persistLearnedHosts(force: Boolean) {
        val file = learnedCacheFile ?: return
        if (!force && !persistDirty.compareAndSet(true, false)) return
        persistDirty.set(false)
        try {
            val cutoff = System.currentTimeMillis() - CLIENT_HOST_TTL_MS
            val rows = ArrayList<String>(MAX_LEARNED_ENTRIES)
            fun appendMap(prefix: String, map: Map<String, LearnedHostEntry>, limit: Int) {
                map.entries
                    .asSequence()
                    .filter { it.value.updatedAtMs >= cutoff }
                    .sortedByDescending { it.value.updatedAtMs }
                    .take(limit)
                    .forEach { (k, v) ->
                        rows.add("$prefix\t$k\t${v.host}\t${v.updatedAtMs}")
                    }
            }
            appendMap("C", learnedHostByClientIpPort, 600)
            appendMap("P", learnedHostByIpPort, 500)
            appendMap("I", learnedHostByIp, 400)

            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.writeText(rows.joinToString("\n"))
            if (!tmp.renameTo(file)) {
                tmp.copyTo(file, overwrite = true)
                tmp.delete()
            }
        } catch (_: Exception) {
        }
    }

    private fun enqueuePtrLookup(remoteIp: String) {
        if (ptrByRemoteIp.size >= 512 || !ptrPending.add(remoteIp)) return
        ptrExecutor.submit {
            try {
                val resolved = InetAddress.getByName(remoteIp).canonicalHostName
                ptrByRemoteIp[remoteIp] = if (resolved.isNotBlank() && resolved != remoteIp) {
                    resolved.lowercase()
                } else {
                    ""
                }
            } catch (_: Exception) {
                ptrByRemoteIp[remoteIp] = ""
            } finally {
                ptrPending.remove(remoteIp)
            }
        }
    }

    private fun finalizeSecondSpeeds() {
        for (device in trafficById.values) {
            device.currentDownloadBps = device.pendingRxBytes
            device.currentUploadBps = device.pendingTxBytes
            device.pendingRxBytes = 0L
            device.pendingTxBytes = 0L
        }
    }

    private fun upsertClientMeta(
        id: String,
        ip: String,
        mac: String?,
        state: String,
        leasesByMac: Map<String, String>,
        leasesByIp: Map<String, String>,
        stationByMac: Map<String, StationStats>,
        now: Long
    ) {
        val prev = clientsById[id]
        val resolvedMac = mac ?: prev?.mac
        val vendorInfo = OuiVendorLookup.lookup(resolvedMac)
        val station = if (resolvedMac != null) stationByMac[resolvedMac] else null
        val preferredIp = if (ip.contains(".")) ip else (prev?.ip ?: ip)
        val hostname = (if (resolvedMac != null) dhcpHostByMac[resolvedMac] else null)
            ?: dhcpHostByIp[preferredIp]
            ?: leasesByIp[preferredIp]
            ?: (if (resolvedMac != null) leasesByMac[resolvedMac] else null)
            ?: prev?.hostname
        val osHint = if (resolvedMac != null) osHintByMac[resolvedMac] else null
        val resolvedVendor = if ((vendorInfo.vendor == "Unknown" || vendorInfo.vendor.startsWith("Unknown (") || vendorInfo.isRandomized) && osHint != null) {
            osHint
        } else {
            vendorInfo.vendor
        }

        val isOnline = when {
            station != null -> true
            state == "REACHABLE" || state == "DELAY" || state == "PROBE" || state == "PERMANENT" -> true
            state == "STALE" || state == "ARP" -> {
                val lastTraffic = trafficById[id]?.lastTrafficMs ?: 0L
                (now - lastTraffic) < 12_000L
            }
            else -> false
        }

        val effectiveLastSeen = if (isOnline) {
            now
        } else {
            maxOf(prev?.lastSeenMs ?: 0L, trafficById[id]?.lastTrafficMs ?: 0L)
        }

        clientsById[id] = RootClientMeta(
            id = id,
            ip = preferredIp,
            mac = resolvedMac,
            hostname = hostname,
            vendor = resolvedVendor,
            isRandomizedMac = vendorInfo.isRandomized,
            neighborState = if (isOnline) state else "OFFLINE",
            rssiDbm = station?.rssiDbm ?: prev?.rssiDbm,
            txBitrateMbps = station?.txBitrateMbps ?: prev?.txBitrateMbps,
            rxBitrateMbps = station?.rxBitrateMbps ?: prev?.rxBitrateMbps,
            isOnline = isOnline,
            lastSeenMs = effectiveLastSeen
        )
    }

    private data class StationStats(
        val rssiDbm: Int?,
        val txBitrateMbps: Double?,
        val rxBitrateMbps: Double?
    )

    private fun parseIwStations(lines: List<String>): Map<String, StationStats> {
        val map = mutableMapOf<String, StationStats>()
        var currentMac: String? = null
        var rssi: Int? = null
        var txMbps: Double? = null
        var rxMbps: Double? = null

        fun flush() {
            val mac = currentMac ?: return
            map[mac] = StationStats(rssi, txMbps, rxMbps)
        }

        for (raw in lines) {
            val line = raw.trim()
            if (line.startsWith("Station ")) {
                flush()
                currentMac = line.removePrefix("Station ").substringBefore(" ").uppercase()
                rssi = null
                txMbps = null
                rxMbps = null
            } else if (line.startsWith("signal:")) {
                rssi = Regex("-?\\d+").find(line)?.value?.toIntOrNull()
            } else if (line.startsWith("tx bitrate:")) {
                txMbps = Regex("\\d+(\\.\\d+)?").find(line)?.value?.toDoubleOrNull()
            } else if (line.startsWith("rx bitrate:")) {
                rxMbps = Regex("\\d+(\\.\\d+)?").find(line)?.value?.toDoubleOrNull()
            }
        }
        flush()
        return map
    }

    private fun parseSections(output: String): Map<String, List<String>> {
        val map = mutableMapOf<String, MutableList<String>>()
        var current = "DEFAULT"
        for (line in output.lines()) {
            when (line.trim()) {
                "---APMAC---" -> current = "APMAC"
                "---NEIGH---" -> current = "NEIGH"
                "---NEIGH6---" -> current = "NEIGH6"
                "---IW---" -> current = "IW"
                "---ARP---" -> current = "ARP"
                "---LEASES---" -> current = "LEASES"
                else -> map.getOrPut(current) { mutableListOf() }.add(line)
            }
        }
        return map
    }

    private fun pokeUdpDiscardAsync(ip: String) {
        if (!ip.contains(".")) return
        ptrExecutor.submit {
            var sock: DatagramSocket? = null
            try {
                sock = DatagramSocket()
                val buf = byteArrayOf(0)
                sock.send(DatagramPacket(buf, buf.size, InetAddress.getByName(ip), 9))
            } catch (_: Exception) {
            } finally {
                try {
                    sock?.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun refreshDhcpRepositoryFromNetworkStack() {
        val out = runSuCommand(
            "dumpsys network_stack 2>/dev/null | grep -i 'hwAddr:' | tail -n 120",
            3
        ) ?: return
        val hwRegex = Regex("hwAddr:\\s*([0-9a-fA-F:]{17})")
        val ipRegex = Regex("netAddr:\\s*([0-9.]+)/\\d+")
        val hostRegex = Regex("hostname:\\s*([^,\\r\\n]+)")

        for (line in out.lines()) {
            val host = hostRegex.find(line)?.groupValues?.getOrNull(1)?.trim() ?: continue
            if (host.isEmpty() ||
                host.equals("null", ignoreCase = true) ||
                host.equals("(null)", ignoreCase = true) ||
                host == "*"
            ) {
                continue
            }
            val mac = hwRegex.find(line)?.groupValues?.getOrNull(1)?.uppercase()
            val ip = ipRegex.find(line)?.groupValues?.getOrNull(1)
            if (!mac.isNullOrBlank()) {
                dhcpHostByMac[mac] = host
                if (!ip.isNullOrBlank()) {
                    dhcpIpByMac[mac] = ip
                }
            }
            if (!ip.isNullOrBlank()) {
                dhcpHostByIp[ip] = host
            }
        }
    }

    private fun runSuCommand(command: String, timeoutSeconds: Long): String? {
        return try {
            val args = suArgsBuilder?.invoke(command) ?: listOf(suCommand, "-c", command)
            val proc = ProcessBuilder(args)
                .redirectErrorStream(true)
                .start()
            if (!proc.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                proc.destroyForcibly()
                return null
            }
            proc.inputStream.bufferedReader().readText()
        } catch (_: Exception) {
            null
        }
    }
}
