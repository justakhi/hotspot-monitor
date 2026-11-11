// Copyright (c) 2026 AP Labs - Akshay Kumar (@justakhi). All rights reserved.
// Licensed under PolyForm Noncommercial License 1.0.0. See LICENSE and NOTICE.

package com.justakhi.hotspot_monitor

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    companion object {
        private const val CONTROL_CHANNEL = "com.justakhi.hotspot_monitor/control"
        private const val TELEMETRY_CHANNEL = "com.justakhi.hotspot_monitor/telemetry"
    }

    private lateinit var capabilityChecker: CapabilityChecker
    private lateinit var nonRootSource: NonRootTelemetrySource
    private val rootSource = RootTelemetrySource()

    private val workerExecutor = Executors.newSingleThreadExecutor()
    private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null
    private var pollFuture: ScheduledFuture<*>? = null

    @Volatile
    private var rootModeEnabled = false

    @Volatile
    private var sessionStartMs = System.currentTimeMillis()

    @Volatile
    private var lastNonRootDevices: List<DiscoveredHost> = emptyList()

    @Volatile
    private var lastSubnetScanMs = 0L

    @Volatile
    private var baselineIfaceRx: Long? = null

    @Volatile
    private var baselineIfaceTx: Long? = null

    @Volatile
    private var activeProbeInterface: String? = null

    @Volatile
    private var lastSessionTotalBytes = 0L

    @Volatile
    private var lastTickMs = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        capabilityChecker = CapabilityChecker(applicationContext)
        nonRootSource = NonRootTelemetrySource(applicationContext)
        rootSource.initStorage(applicationContext.filesDir)
        rootSource.suCommand = capabilityChecker.resolveSuExecutable() ?: "su"
        rootSource.suArgsBuilder = { cmd -> capabilityChecker.buildSuArgs(cmd) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TELEMETRY_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startTelemetryLoop()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopTelemetryLoop()
                }
            })
    }

    override fun onDestroy() {
        stopTelemetryLoop()
        nonRootSource.stopMdnsDiscovery()
        rootSource.stopProbe()
        workerExecutor.shutdownNow()
        scheduler.shutdownNow()
        super.onDestroy()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> {
                workerExecutor.execute {
                    val snap = capabilityChecker.snapshot(rootModeEnabled)
                    mainHandler.post { result.success(snap.toMap()) }
                }
            }
            "openUsageAccessSettings" -> {
                capabilityChecker.openUsageAccessSettings()
                result.success(true)
            }
            "openUrl" -> {
                val url = call.argument<String>("url")?.trim()
                val opened = if (!url.isNullOrBlank() && (url.startsWith("https://") || url.startsWith("http://"))) {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        true
                    } catch (_: Exception) {
                        false
                    }
                } else {
                    false
                }
                result.success(opened)
            }
            "requestRootAccess" -> {
                workerExecutor.execute {
                    val granted = capabilityChecker.requestRootAccess()
                    if (granted) {
                        rootSource.suCommand = capabilityChecker.resolveSuExecutable() ?: "su"
                        rootModeEnabled = true
                        restartRootProbeIfNeeded()
                    }
                    val snap = capabilityChecker.snapshot(rootModeEnabled)
                    mainHandler.post { result.success(snap.toMap()) }
                }
            }
            "setRootModeEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                workerExecutor.execute {
                    if (enabled && !capabilityChecker.rootGrantedCached) {
                        val granted = capabilityChecker.requestRootAccess()
                        rootModeEnabled = granted
                    } else {
                        rootModeEnabled = enabled && capabilityChecker.rootGrantedCached
                    }
                    if (rootModeEnabled) {
                        restartRootProbeIfNeeded()
                    } else {
                        rootSource.stopProbe()
                        activeProbeInterface = null
                    }
                    val snap = capabilityChecker.snapshot(rootModeEnabled)
                    mainHandler.post { result.success(snap.toMap()) }
                }
            }
            "resetSession" -> {
                workerExecutor.execute {
                    sessionStartMs = System.currentTimeMillis()
                    lastSessionTotalBytes = 0L
                    lastTickMs = 0L
                    baselineIfaceRx = null
                    baselineIfaceTx = null
                    rootSource.resetSession()
                    lastNonRootDevices = emptyList()
                    lastSubnetScanMs = 0L
                    mainHandler.post { result.success(true) }
                }
            }
            "scanNow" -> {
                workerExecutor.execute {
                    val snap = capabilityChecker.snapshot(rootModeEnabled)
                    if (!rootModeEnabled && snap.hotspot.active && !snap.hotspot.gatewayIp.isNullOrBlank()) {
                        lastNonRootDevices = nonRootSource.scanSubnetDevices(
                            snap.hotspot.gatewayIp,
                            snap.hotspot.prefixLength
                        )
                        lastSubnetScanMs = System.currentTimeMillis()
                    }
                    val payload = collectTelemetryPayload(snap)
                    mainHandler.post {
                        eventSink?.success(payload)
                        result.success(payload)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun startTelemetryLoop() {
        stopTelemetryLoop()
        nonRootSource.startMdnsDiscovery()
        if (rootModeEnabled) {
            workerExecutor.execute { restartRootProbeIfNeeded() }
        }
        pollFuture = scheduler.scheduleWithFixedDelay(
            {
                try {
                    val snap = capabilityChecker.snapshot(rootModeEnabled)
                    if (rootModeEnabled) {
                        ensureRootProbeRunning(snap.hotspot)
                    } else if (snap.hotspot.active && !snap.hotspot.gatewayIp.isNullOrBlank()) {
                        val now = System.currentTimeMillis()
                        if (now - lastSubnetScanMs >= 8000L) {
                            lastSubnetScanMs = now
                            lastNonRootDevices = nonRootSource.scanSubnetDevices(
                                snap.hotspot.gatewayIp,
                                snap.hotspot.prefixLength
                            )
                        }
                    } else {
                        lastNonRootDevices = emptyList()
                    }

                    val payload = collectTelemetryPayload(snap)
                    mainHandler.post { eventSink?.success(payload) }
                } catch (_: Exception) {
                }
            },
            0L,
            2000L,
            TimeUnit.MILLISECONDS
        )
    }

    private fun stopTelemetryLoop() {
        pollFuture?.cancel(false)
        pollFuture = null
        nonRootSource.stopMdnsDiscovery()
        rootSource.stopProbe()
        activeProbeInterface = null
    }

    private fun restartRootProbeIfNeeded() {
        val hotspot = capabilityChecker.detectHotspotInterface(useRootIfGranted = true)
        ensureRootProbeRunning(hotspot, forceRestart = true)
    }

    private fun ensureRootProbeRunning(hotspot: HotspotInterfaceInfo, forceRestart: Boolean = false) {
        if (!rootModeEnabled || !hotspot.active || hotspot.interfaceName.isNullOrBlank() || hotspot.gatewayIp.isNullOrBlank()) {
            if (activeProbeInterface != null) {
                rootSource.stopProbe()
                activeProbeInterface = null
            }
            return
        }
        if (forceRestart || activeProbeInterface != hotspot.interfaceName || !rootSource.probeActive) {
            activeProbeInterface = hotspot.interfaceName
            rootSource.startProbe(
                probeBinary = capabilityChecker.probeProbeBinary(),
                iface = hotspot.interfaceName,
                gatewayIp = hotspot.gatewayIp,
                prefixLength = hotspot.prefixLength
            )
        }
    }

    private fun collectTelemetryPayload(snap: CapabilitySnapshot): Map<String, Any?> {
        val now = System.currentTimeMillis()

        var sessionDownloadBytes = 0L
        var sessionUploadBytes = 0L
        var liveDownBps = 0L
        var liveUpBps = 0L
        val devicesPayload: List<Map<String, Any?>>

        if (rootModeEnabled) {
            val rawDevices = rootSource.refreshClients(
                snap.hotspot.interfaceName,
                snap.hotspot.gatewayIp,
                nonRootSource.getKnownHostnames()
            )
            for (d in rawDevices) {
                val ip = d["ip"] as? String
                val host = d["hostname"] as? String
                if (!ip.isNullOrBlank() && host.isNullOrBlank()) {
                    nonRootSource.enrichHostnameAsync(ip)
                }
            }
            devicesPayload = rawDevices

            // Aggregate per-device counters from packet probe; cross-check interface counters if probe sees less.
            var probeDown = 0L
            var probeUp = 0L
            for (d in devicesPayload) {
                probeDown += (d["downloadBytes"] as? Long) ?: 0L
                probeUp += (d["uploadBytes"] as? Long) ?: 0L
                liveDownBps += (d["currentDownloadBps"] as? Long) ?: 0L
                liveUpBps += (d["currentUploadBps"] as? Long) ?: 0L
            }

            val ifaceTotals = rootSource.readInterfaceTotals(snap.hotspot.interfaceName)
            if (ifaceTotals != null) {
                if (baselineIfaceRx == null || baselineIfaceTx == null ||
                    ifaceTotals.first < baselineIfaceTx!! || ifaceTotals.second < baselineIfaceRx!!
                ) {
                    baselineIfaceTx = ifaceTotals.first
                    baselineIfaceRx = ifaceTotals.second
                }
                val ifaceDown = (ifaceTotals.first - (baselineIfaceTx ?: 0L)).coerceAtLeast(0L)
                val ifaceUp = (ifaceTotals.second - (baselineIfaceRx ?: 0L)).coerceAtLeast(0L)
                sessionDownloadBytes = maxOf(probeDown, ifaceDown)
                sessionUploadBytes = maxOf(probeUp, ifaceUp)
            } else {
                sessionDownloadBytes = probeDown
                sessionUploadBytes = probeUp
            }
        } else {
            val tether = nonRootSource.queryTetherUsage(sessionStartMs, now)
            sessionDownloadBytes = tether.downloadBytes
            sessionUploadBytes = tether.uploadBytes
            val totalNow = sessionDownloadBytes + sessionUploadBytes
            if (lastTickMs > 0L && now > lastTickMs && totalNow >= lastSessionTotalBytes) {
                val dtSec = ((now - lastTickMs) / 1000.0).coerceAtLeast(1.0)
                liveDownBps = ((totalNow - lastSessionTotalBytes) / dtSec).toLong()
            }
            lastSessionTotalBytes = totalNow
            lastTickMs = now

            devicesPayload = lastNonRootDevices.map { host ->
                mapOf(
                    "id" to host.ip,
                    "ip" to host.ip,
                    "mac" to null,
                    "hostname" to host.hostname,
                    "vendor" to "Root required for MAC/Vendor",
                    "isRandomizedMac" to false,
                    "neighborState" to host.discoveryMethod.uppercase(),
                    "rssiDbm" to null,
                    "txBitrateMbps" to null,
                    "rxBitrateMbps" to null,
                    "isOnline" to true,
                    "lastSeenMs" to now,
                    "downloadBytes" to 0L,
                    "uploadBytes" to 0L,
                    "currentDownloadBps" to 0L,
                    "currentUploadBps" to 0L,
                    "services" to emptyList<Map<String, Any>>()
                )
            }
        }

        return mapOf(
            "timestampMs" to now,
            "sessionStartMs" to sessionStartMs,
            "mode" to if (rootModeEnabled) "root" else "non_root",
            "capabilities" to snap.toMap(),
            "probeActive" to rootSource.probeActive,
            "probeError" to rootSource.probeError,
            "sessionDownloadBytes" to sessionDownloadBytes,
            "sessionUploadBytes" to sessionUploadBytes,
            "liveDownloadBps" to liveDownBps,
            "liveUploadBps" to liveUpBps,
            "devices" to devicesPayload
        )
    }
}
