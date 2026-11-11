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

    fun scanSubnetDevices(gatewayIp: String, prefixLength: Int): List<DiscoveredHost> {
        val baseParts = gatewayIp.split(".").mapNotNull { it.toIntOrNull() }
        if (baseParts.size != 4) return emptyList()

        val gwInt = (baseParts[0] shl 24) or (baseParts[1] shl 16) or (baseParts[2] shl 8) or baseParts[3]
        val clampedPrefix = prefixLength.coerceIn(24, 30)
        val hostBits = 32 - clampedPrefix
        val hostCount = (1 shl hostBits) - 2
        val networkInt = gwInt and (-1 shl hostBits)

        val candidateIps = mutableListOf<String>()
        for (offset in 1..hostCount.coerceAtMost(254)) {
            val ipInt = networkInt or offset
            if (ipInt == gwInt) continue
            val ip = "${(ipInt ushr 24) and 0xFF}.${(ipInt ushr 16) and 0xFF}.${(ipInt ushr 8) and 0xFF}.${ipInt and 0xFF}"
            candidateIps.add(ip)
        }

        val futures = mutableListOf<Future<DiscoveredHost?>>()
        for (ip in candidateIps) {
            futures.add(scanExecutor.submit<DiscoveredHost?> {
                probeHost(ip)
            })
        }

        val found = mutableListOf<DiscoveredHost>()
        for (future in futures) {
            try {
                future.get()?.let { found.add(it) }
            } catch (_: Exception) {
            }
        }
        return found
    }

    private fun probeHost(ip: String): DiscoveredHost? {
        var alive = false
        var method = "subnet_probe"

        try {
            val addr = InetAddress.getByName(ip)
            if (addr.isReachable(180)) {
                alive = true
                method = "icmp_echo"
            }
        } catch (_: Exception) {
        }

        if (!alive) {
            val probePorts = intArrayOf(62078, 80, 443, 8008, 5555, 5353)
            for (port in probePorts) {
                val socket = Socket()
                try {
                    socket.connect(InetSocketAddress(ip, port), 130)
                    alive = true
                    method = "tcp_$port"
                    break
                } catch (_: ConnectException) {
                    // Connection refused proves the peer's TCP/IP stack actively responded.
                    alive = true
                    method = "tcp_rst"
                    break
                } catch (_: Exception) {
                } finally {
                    try {
                        socket.close()
                    } catch (_: Exception) {
                    }
                }
            }
        }

        if (!alive && !mdnsHostNames.containsKey(ip)) {
            return null
        }

        var hostname = mdnsHostNames[ip] ?: resolvedHostNames[ip]
        if (hostname.isNullOrBlank()) {
            hostname = resolveBestHostname(ip)
            if (!hostname.isNullOrBlank()) {
                resolvedHostNames[ip] = hostname
            }
        }
        if (mdnsHostNames.containsKey(ip)) {
            method = "mdns"
        }

        return DiscoveredHost(ip = ip, hostname = hostname, discoveryMethod = method)
    }

    private fun resolveBestHostname(ip: String): String? {
        queryNetBiosName(ip)?.let { return it }
        queryLlmnrPtr(ip)?.let { return it }
        querySsdpFriendlyName(ip)?.let { return it }
        try {
            val canonical = InetAddress.getByName(ip).canonicalHostName
            if (canonical.isNotBlank() && canonical != ip) {
                return canonical.removeSuffix(".local").removeSuffix(".")
            }
        } catch (_: Exception) {
        }
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
