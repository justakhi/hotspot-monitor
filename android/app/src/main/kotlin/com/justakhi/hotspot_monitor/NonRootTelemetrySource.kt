package com.justakhi.hotspot_monitor

import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import java.net.ConnectException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future

data class TetherUsageResult(
    val downloadBytes: Long,
    val uploadBytes: Long,
    val available: Boolean
)

data class DiscoveredHost(
    val ip: String,
    val mac: String? = null,
    val hostname: String?,
    val discoveryMethod: String
)

class NonRootTelemetrySource(private val context: Context) {
    private val mdnsHostNames = ConcurrentHashMap<String, String>()
    private val resolvedHostNames = ConcurrentHashMap<String, String>()
    private var nsdManager: NsdManager? = null
    private val activeListeners = mutableListOf<NsdManager.DiscoveryListener>()
    private var multicastLock: WifiManager.MulticastLock? = null
    private val scanExecutor = Executors.newFixedThreadPool(32)

    fun getKnownHostnames(): Map<String, String> {
        val merged = HashMap<String, String>(resolvedHostNames)
        merged.putAll(mdnsHostNames)
        return merged
    }

    fun enrichHostnameAsync(ip: String) {
        if (!ip.contains(".") || mdnsHostNames.containsKey(ip) || resolvedHostNames.containsKey(ip)) {
            return
        }
        scanExecutor.submit {
            resolveBestHostname(ip)?.let { name ->
                resolvedHostNames[ip] = name
            }
        }
    }

    fun startMdnsDiscovery() {
        stopMdnsDiscovery()
        try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifiManager?.createMulticastLock("HotspotMonitorMdns")?.apply {
                setReferenceCounted(false)
                acquire()
            }
            val manager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return
            nsdManager = manager
            val serviceTypes = listOf(
                "_workstation._tcp.",
                "_smb._tcp.",
                "_afpovertcp._tcp.",
                "_adb-tls-connect._tcp.",
                "_adb._tcp.",
                "_androidtvremote2._tcp.",
                "_spotify-connect._tcp.",
                "_http._tcp.",
                "_googlecast._tcp.",
                "_airplay._tcp.",
                "_companion-link._tcp.",
                "_device-info._tcp."
            )
            for (type in serviceTypes) {
                val listener = createDiscoveryListener(manager)
                activeListeners.add(listener)
                manager.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
            }
        } catch (_: Exception) {
        }
    }

    fun stopMdnsDiscovery() {
        val manager = nsdManager
        if (manager != null) {
            for (listener in activeListeners) {
                try {
                    manager.stopServiceDiscovery(listener)
                } catch (_: Exception) {
                }
            }
        }
        activeListeners.clear()
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Exception) {
        }
        multicastLock = null
    }

    @Suppress("DEPRECATION")
    fun queryTetherUsage(startTimeMs: Long, endTimeMs: Long): TetherUsageResult {
        val statsManager = context.getSystemService(Context.NETWORK_STATS_SERVICE) as? NetworkStatsManager
            ?: return TetherUsageResult(0L, 0L, false)

        var rxTotal = 0L
        var txTotal = 0L
        var anySuccess = false

        val networkTypes = listOf(ConnectivityManager.TYPE_MOBILE, ConnectivityManager.TYPE_WIFI)
        for (netType in networkTypes) {
            try {
                val stats = statsManager.querySummary(netType, null, startTimeMs, endTimeMs)
                anySuccess = true
                val bucket = NetworkStats.Bucket()
                while (stats.hasNextBucket()) {
                    stats.getNextBucket(bucket)
                    if (bucket.uid == NetworkStats.Bucket.UID_TETHERING) {
                        rxTotal += bucket.rxBytes
                        txTotal += bucket.txBytes
                    }
                }
                stats.close()
            } catch (_: SecurityException) {
            } catch (_: Exception) {
            }
        }

        return TetherUsageResult(
            downloadBytes = rxTotal,
            uploadBytes = txTotal,
            available = anySuccess
        )
    }

    fun scanSubnetDevices(gatewayIp: String, prefixLength: Int, ifaceName: String? = null): List<DiscoveredHost> {
        val foundMap = mutableMapOf<String, DiscoveredHost>()

        // 1. Query kernel neighbors table (ip neigh show) - provides exact connected hosts and MAC addresses
        for (kHost in queryKernelNeighbors(ifaceName)) {
            foundMap[kHost.ip] = kHost
            enrichHostnameAsync(kHost.ip)
        }

        // 2. Broadcast sweep (NetBIOS & SSDP broadcasts to subnet & 255.255.255.255)
        for (bHost in broadcastDiscoverHosts(gatewayIp, prefixLength)) {
            if (!foundMap.containsKey(bHost.ip)) {
                foundMap[bHost.ip] = bHost
                enrichHostnameAsync(bHost.ip)
            }
        }

        val baseParts = gatewayIp.split(".").mapNotNull { it.toIntOrNull() }
        if (baseParts.size == 4) {
            val gwInt = (baseParts[0] shl 24) or (baseParts[1] shl 16) or (baseParts[2] shl 8) or baseParts[3]
            val clampedPrefix = prefixLength.coerceIn(24, 30)
            val hostBits = 32 - clampedPrefix
            val hostCount = (1 shl hostBits) - 2
            val networkInt = gwInt and (-1 shl hostBits)
            val routerInt = networkInt or 1 // .1 is upstream router/gateway on shared subnets

            val candidateIps = mutableListOf<String>()

            // Priority IPs
            for (knownIp in resolvedHostNames.keys) {
                if (knownIp.contains(".") && !candidateIps.contains(knownIp)) {
                    candidateIps.add(knownIp)
                }
            }
            for (mdnsIp in mdnsHostNames.keys) {
                if (mdnsIp.contains(".") && !candidateIps.contains(mdnsIp)) {
                    candidateIps.add(mdnsIp)
                }
            }
            for (kIp in foundMap.keys) {
                if (!candidateIps.contains(kIp)) {
                    candidateIps.add(kIp)
                }
            }
            for (arpIp in tryReadArpTable()) {
                if (!candidateIps.contains(arpIp)) {
                    candidateIps.add(arpIp)
                }
            }

            // Subnet sweep
            val offsets = buildList {
                for (o in 100..150) add(o)
                for (o in 2..60) add(o)
                for (o in 1..hostCount.coerceAtMost(254)) {
                    if (o !in 100..150 && o !in 2..60) add(o)
                }
            }.distinct()

            for (offset in offsets) {
                val ipInt = networkInt or offset
                if (ipInt == gwInt || ipInt == routerInt) continue
                val ip = "${(ipInt ushr 24) and 0xFF}.${(ipInt ushr 16) and 0xFF}.${(ipInt ushr 8) and 0xFF}.${ipInt and 0xFF}"
                if (!candidateIps.contains(ip)) {
                    candidateIps.add(ip)
                }
            }

            val futures = mutableListOf<Future<DiscoveredHost?>>()
            for (ip in candidateIps) {
                futures.add(scanExecutor.submit<DiscoveredHost?> {
                    probeHost(ip)
                })
            }

            for (future in futures) {
                try {
                    future.get()?.let { host ->
                        val existing = foundMap[host.ip]
                        if (existing != null) {
                            foundMap[host.ip] = existing.copy(
                                hostname = host.hostname ?: existing.hostname,
                                mac = existing.mac ?: host.mac
                            )
                        } else {
                            foundMap[host.ip] = host
                        }
                    }
                } catch (_: Exception) {
                }
            }
        }

        return foundMap.values.toList()
    }

    fun queryKernelNeighbors(ifaceName: String?): List<DiscoveredHost> {
        val hosts = mutableListOf<DiscoveredHost>()
        val cmd = if (!ifaceName.isNullOrBlank()) {
            listOf("ip", "neigh", "show", "dev", ifaceName)
        } else {
            listOf("ip", "neigh")
        }
        try {
            val process = ProcessBuilder(cmd)
                .redirectErrorStream(true)
                .start()
            val completed = process.waitFor(1, java.util.concurrent.TimeUnit.SECONDS)
            if (completed && process.exitValue() == 0) {
                process.inputStream.bufferedReader().forEachLine { rawLine ->
                    val line = rawLine.trim()
                    if (!line.contains(".") || !line.contains("lladdr")) return@forEachLine
                    val tokens = line.split("\\s+".toRegex())
                    val ip = tokens.getOrNull(0) ?: return@forEachLine
                    if (!ip.contains(".")) return@forEachLine
                    val lladdrIndex = tokens.indexOf("lladdr")
                    val mac = if (lladdrIndex >= 0 && lladdrIndex + 1 < tokens.size) {
                        tokens[lladdrIndex + 1].uppercase()
                    } else null
                    val state = tokens.lastOrNull()?.uppercase() ?: ""
                    val isAlive = state == "REACHABLE" || state == "DELAY" || state == "STALE" || state == "PERMANENT"
                    if (isAlive && mac != null && mac != "00:00:00:00:00:00") {
                        val hostname = mdnsHostNames[ip] ?: resolvedHostNames[ip]
                        hosts.add(
                            DiscoveredHost(
                                ip = ip,
                                mac = mac,
                                hostname = hostname,
                                discoveryMethod = "kernel_$state".lowercase()
                            )
                        )
                    }
                }
            } else {
                process.destroyForcibly()
            }
        } catch (_: Exception) {
        }
        return hosts
    }

    private fun tryReadArpTable(): List<String> {
        val ips = mutableListOf<String>()
        try {
            val file = java.io.File("/proc/net/arp")
            if (file.exists() && file.canRead()) {
                file.forEachLine { line ->
                    val tokens = line.split("\\s+".toRegex())
                    if (tokens.size >= 4 && tokens[0] != "IP") {
                        val ip = tokens[0]
                        val flags = tokens[2]
                        if (flags != "0x0" && ip.contains(".")) {
                            ips.add(ip)
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }
        return ips
    }

    private fun broadcastDiscoverHosts(gatewayIp: String, prefixLength: Int): List<DiscoveredHost> {
        val discovered = mutableListOf<DiscoveredHost>()
        val baseParts = gatewayIp.split(".").mapNotNull { it.toIntOrNull() }
        if (baseParts.size != 4) return discovered

        val gwInt = (baseParts[0] shl 24) or (baseParts[1] shl 16) or (baseParts[2] shl 8) or baseParts[3]
        val clampedPrefix = prefixLength.coerceIn(24, 30)
        val hostBits = 32 - clampedPrefix
        val broadcastInt = (gwInt and (-1 shl hostBits)) or ((1 shl hostBits) - 1)
        val bcastIp = "${(broadcastInt ushr 24) and 0xFF}.${(broadcastInt ushr 16) and 0xFF}.${(broadcastInt ushr 8) and 0xFF}.${broadcastInt and 0xFF}"

        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            socket.broadcast = true
            socket.soTimeout = 250

            // 1. NetBIOS Node Status Broadcast to subnet broadcast & global broadcast
            val nbReq = byteArrayOf(
                0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x20, 0x43, 0x4B, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
                0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
                0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x00, 0x00, 0x21, 0x00, 0x01
            )
            socket.send(DatagramPacket(nbReq, nbReq.size, InetAddress.getByName(bcastIp), 137))
            socket.send(DatagramPacket(nbReq, nbReq.size, InetAddress.getByName("255.255.255.255"), 137))

            // 2. SSDP M-SEARCH broadcast
            val ssdp = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n"
            val ssdpBytes = ssdp.toByteArray(Charsets.US_ASCII)
            socket.send(DatagramPacket(ssdpBytes, ssdpBytes.size, InetAddress.getByName("239.255.255.250"), 1900))
            socket.send(DatagramPacket(ssdpBytes, ssdpBytes.size, InetAddress.getByName(bcastIp), 1900))

            // Listen for replies
            val buf = ByteArray(2048)
            val startTime = System.currentTimeMillis()
            while (System.currentTimeMillis() - startTime < 300) {
                try {
                    val p = DatagramPacket(buf, buf.size)
                    socket.receive(p)
                    val senderIp = p.address.hostAddress ?: continue
                    if (senderIp == gatewayIp || senderIp == "127.0.0.1") continue
                    val hostname = parseNetBiosResponse(buf, p.length)
                    if (!hostname.isNullOrBlank()) {
                        resolvedHostNames[senderIp] = hostname
                    }
                    discovered.add(
                        DiscoveredHost(
                            ip = senderIp,
                            hostname = hostname ?: mdnsHostNames[senderIp],
                            discoveryMethod = "broadcast"
                        )
                    )
                } catch (_: java.net.SocketTimeoutException) {
                    break
                }
            }
        } catch (_: Exception) {
        } finally {
            try { socket?.close() } catch (_: Exception) {}
        }
        return discovered
    }

    private fun probeHost(ip: String): DiscoveredHost? {
        // 1. Fast check: is it already known in mDNS?
        if (mdnsHostNames.containsKey(ip)) {
            return DiscoveredHost(
                ip = ip,
                hostname = mdnsHostNames[ip],
                discoveryMethod = "mdns"
            )
        }

        var alive = false
        var method = "unknown"

        // 2. Ultra-fast TCP port handshake & RST check across primary OS ports (60ms timeout)
        // 7680: Windows 10/11 Delivery Optimization (open by default on all Windows 10/11 even on Public profile!)
        // 80: HTTP (Web, Android, Routers, IoT)
        // 443: HTTPS
        // 62078: Apple iOS / iPadOS WiFi sync / lockdownd
        // 8008: Google Cast / Chromecast / Android TV
        // 5555: Android ADB
        // 5357: Windows WSD
        // 445: SMB
        // 22: Linux / SSH
        val quickPorts = intArrayOf(7680, 80, 443, 62078, 8008, 5555, 5357, 445, 139, 135, 22)
        for (port in quickPorts) {
            val socket = Socket()
            try {
                socket.connect(InetSocketAddress(ip, port), 60)
                alive = true
                method = when (port) {
                    7680 -> "tcp_7680 (Windows)"
                    62078 -> "tcp_62078 (Apple iOS)"
                    8008 -> "tcp_8008 (Google Cast)"
                    5555 -> "tcp_5555 (Android)"
                    5357 -> "tcp_5357 (Windows)"
                    445, 139, 135 -> "tcp_$port (SMB/Windows)"
                    22 -> "tcp_22 (Linux/SSH)"
                    else -> "tcp_$port"
                }
                break
            } catch (_: ConnectException) {
                // TCP RST received! Irrefutable proof host is online.
                alive = true
                method = "tcp_rst_$port"
                break
            } catch (_: Exception) {
            } finally {
                try {
                    socket.close()
                } catch (_: Exception) {
                }
            }
        }

        // 3. Fast ICMP ping fallback (100ms)
        if (!alive) {
            try {
                val proc = ProcessBuilder("/system/bin/ping", "-c", "1", "-w", "1", ip)
                    .redirectErrorStream(true)
                    .start()
                if (proc.waitFor(100, java.util.concurrent.TimeUnit.MILLISECONDS) && proc.exitValue() == 0) {
                    alive = true
                    method = "ping"
                } else {
                    proc.destroyForcibly()
                }
            } catch (_: Exception) {
            }
        }

        if (!alive) {
            return null
        }

        // Host IS confirmed alive. Resolve best available hostname.
        var hostname = mdnsHostNames[ip] ?: resolvedHostNames[ip]
        if (hostname.isNullOrBlank()) {
            hostname = resolveBestHostname(ip)
            if (!hostname.isNullOrBlank()) {
                resolvedHostNames[ip] = hostname
            }
        }

        return DiscoveredHost(ip = ip, hostname = hostname, discoveryMethod = method)
    }

    private fun resolveBestHostname(ip: String): String? {
        try {
            val canonical = InetAddress.getByName(ip).canonicalHostName
            if (canonical.isNotBlank() && canonical != ip) {
                return canonical.removeSuffix(".local").removeSuffix(".")
            }
        } catch (_: Exception) {
        }
        queryNetBiosName(ip)?.let { return it }
        queryLlmnrPtr(ip)?.let { return it }
        querySsdpFriendlyName(ip)?.let { return it }
        return null
    }

    private fun queryLlmnrPtr(ip: String): String? {
        // LLMNR (UDP 5355) PTR query for reverse IP (<d>.<c>.<b>.<a>.in-addr.arpa).
        val parts = ip.split(".")
        if (parts.size != 4) return null
        val labels = listOf(parts[3], parts[2], parts[1], parts[0], "in-addr", "arpa")
        val packet = mutableListOf<Byte>(
            0x12, 0x34, // Transaction ID
            0x00, 0x00, // Standard query
            0x00, 0x01, // 1 question
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        )
        for (lbl in labels) {
            val bytes = lbl.toByteArray(Charsets.US_ASCII)
            packet.add(bytes.size.toByte())
            for (b in bytes) packet.add(b)
        }
        packet.add(0x00) // root label
        packet.add(0x00); packet.add(0x0C) // PTR
        packet.add(0x00); packet.add(0x01) // IN

        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            socket.soTimeout = 180
            val reqBytes = packet.toByteArray()
            socket.send(DatagramPacket(reqBytes, reqBytes.size, InetAddress.getByName(ip), 5355))
            val buf = ByteArray(512)
            val resp = DatagramPacket(buf, buf.size)
            socket.receive(resp)
            parseDnsPtrResponse(buf, resp.length)
        } catch (_: Exception) {
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun parseDnsPtrResponse(buf: ByteArray, len: Int): String? {
        if (len < 12) return null
        val ancount = ((buf[6].toInt() and 0xFF) shl 8) or (buf[7].toInt() and 0xFF)
        if (ancount <= 0) return null
        var pos = 12
        // Skip question name + qtype + qclass
        while (pos < len) {
            val l = buf[pos].toInt() and 0xFF
            if (l == 0) {
                pos += 5
                break
            }
            if ((l and 0xC0) == 0xC0) {
                pos += 6
                break
            }
            pos += 1 + l
        }
        if (pos + 12 > len) return null
        val nameOffset = pos
        val rtype = ((buf[nameOffset + 2].toInt() and 0xFF) shl 8) or (buf[nameOffset + 3].toInt() and 0xFF)
        val rdlenPos = if ((buf[nameOffset].toInt() and 0xC0) == 0xC0) nameOffset + 10 else nameOffset + 10
        if (rtype != 12 || rdlenPos > len) return null
        val sb = StringBuilder()
        var p = rdlenPos
        var jumps = 0
        while (p < len && jumps < 6) {
            val l = buf[p].toInt() and 0xFF
            if (l == 0) break
            if ((l and 0xC0) == 0xC0) {
                if (p + 1 >= len) break
                p = ((l and 0x3F) shl 8) or (buf[p + 1].toInt() and 0xFF)
                jumps++
                continue
            }
            if (p + 1 + l > len) break
            if (sb.isNotEmpty()) sb.append('.')
            sb.append(String(buf, p + 1, l, Charsets.UTF_8))
            p += 1 + l
        }
        val raw = sb.toString().trim().removeSuffix(".local").removeSuffix(".")
        return raw.ifEmpty { null }
    }

    private fun querySsdpFriendlyName(ip: String): String? {
        val search = "M-SEARCH * HTTP/1.1\r\nHOST: $ip:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n"
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            socket.soTimeout = 180
            val bytes = search.toByteArray(Charsets.US_ASCII)
            socket.send(DatagramPacket(bytes, bytes.size, InetAddress.getByName(ip), 1900))
            val buf = ByteArray(1024)
            val resp = DatagramPacket(buf, buf.size)
            socket.receive(resp)
            val text = String(buf, 0, resp.length, Charsets.UTF_8)
            val loc = Regex("(?im)^LOCATION:\\s*(http://[^\\r\\n]+)").find(text)?.groupValues?.getOrNull(1)?.trim()
                ?: return null
            val conn = java.net.URL(loc).openConnection() as java.net.HttpURLConnection
            conn.connectTimeout = 250
            conn.readTimeout = 250
            val xml = conn.inputStream.bufferedReader().use { it.readText() }
            Regex("<friendlyName>([^<]+)</friendlyName>").find(xml)?.groupValues?.getOrNull(1)?.trim()
                ?: Regex("<modelName>([^<]+)</modelName>").find(xml)?.groupValues?.getOrNull(1)?.trim()
        } catch (_: Exception) {
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun queryNetBiosName(ip: String): String? {
        // NetBIOS Node Status (NBSTAT) UDP 137 request for Windows / Samba / macOS hostnames.
        val request = byteArrayOf(
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Flags
            0x00, 0x01, // Questions: 1
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x20, 0x43, 0x4B,
            0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
            0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
            0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
            0x00,
            0x00, 0x21, // Type: NBSTAT
            0x00, 0x01  // Class: IN
        )
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            socket.soTimeout = 220
            val addr = InetAddress.getByName(ip)
            socket.send(DatagramPacket(request, request.size, addr, 137))
            val buf = ByteArray(1024)
            val resp = DatagramPacket(buf, buf.size)
            socket.receive(resp)
            parseNetBiosResponse(buf, resp.length)
        } catch (_: Exception) {
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun parseNetBiosResponse(buf: ByteArray, len: Int): String? {
        if (len < 57) return null
        val numNames = buf[56].toInt() and 0xFF
        var pos = 57
        for (i in 0 until numNames) {
            if (pos + 18 > len) break
            val rawName = String(buf, pos, 15, Charsets.US_ASCII).trim()
            val suffix = buf[pos + 15].toInt() and 0xFF
            val flags = ((buf[pos + 16].toInt() and 0xFF) shl 8) or (buf[pos + 17].toInt() and 0xFF)
            val isGroup = (flags and 0x8000) != 0
            if (!isGroup && suffix == 0x00 && rawName.isNotEmpty() && !rawName.startsWith("__")) {
                return rawName
            }
            pos += 18
        }
        return null
    }

    private fun createDiscoveryListener(manager: NsdManager): NsdManager.DiscoveryListener {
        return object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {}
            override fun onDiscoveryStarted(serviceType: String?) {}
            override fun onDiscoveryStopped(serviceType: String?) {}
            override fun onServiceLost(serviceInfo: NsdServiceInfo?) {}

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                try {
                    @Suppress("DEPRECATION")
                    manager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo?, errorCode: Int) {}
                        override fun onServiceResolved(resolved: NsdServiceInfo) {
                            @Suppress("DEPRECATION")
                            val hostAddr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                resolved.hostAddresses.firstOrNull()?.hostAddress
                            } else {
                                resolved.host?.hostAddress
                            }
                            if (!hostAddr.isNullOrBlank()) {
                                val cleanName = resolved.serviceName.trim()
                                if (cleanName.isNotEmpty()) {
                                    mdnsHostNames[hostAddr] = cleanName
                                }
                            }
                        }
                    })
                } catch (_: Exception) {
                }
            }
        }
    }
}
