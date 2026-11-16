# Changelog

All notable changes to Hotspot Monitor are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-11-16

### Added
- **Native dark splash screen**: Android 12+ SplashScreen API integration with deep slate `#090A0E` background and centered app icon, eliminating the blank white startup screen.
- **Pulsing skeleton loader**: Startup placeholder cards that mirror the dashboard layout, replacing the circular spinner.
- **Fast non-root host detection**: High-speed multi-OS TCP handshake probes (Windows WUDO port 7680, Apple Continuity 62078, Cast 8008, ADB 5555, Web 80/443). Probes /24 hotspot subnets in ~350ms and identifies connected Windows machines even under Public network profile.
- **Automatic OS fingerprinting**: Infers and displays client vendor (`Microsoft Windows Device`, `Apple Device`, `Android Device`) when MAC address is hidden by Android 14 SELinux restrictions.
- **Usage & log data export**: Export hotspot traffic, upstream network info, and connection logs to standard CSV and JSON with ISO 8601 timestamps, developer credits, and GitHub project link.
- **Quick hotspot toggle**: One-tap toggle and settings launcher for mobile hotspot on both root and non-root setups.
- **Background foreground service**: Persistent background monitor notification with battery optimization whitelist support.
- **Session quota controls**: Set session bandwidth limits with proactive 80% warning and overage indicators.
- **Per-device access controls (root mode)**: In-memory `iptables` internet blocking and individual client data limits.

### Fixed
- **Device rename dialog crash**: Fixed `failed assertion line 6281 pos 12: true` when canceling the rename dialog by scoping controller lifecycle within the stateful dialog widget.
- **Non-root 0 connected devices bug**: Resolved issue where Android 11+ SELinux blocked `/proc/net/arp` and `ip neigh` by using active TCP port scanning.

---

## [1.0.0] - 2026-11-15

### Added
- **Live hotspot telemetry**: Real-time download/upload speed gauges and cumulative session byte tracking.
- **Deep packet inspection (root mode)**: Passive C probe (`libhs_probe.so`) sniffing TLS ClientHello SNI, QUIC initial packets, and DNS queries without acting as a proxy or breaking certificate validation.
- **Automatic service classification**: Maps network flows to friendly categories (YouTube, Netflix, Instagram, Google, Steam, GitHub, System Updates, etc.).
- **Non-root compatibility**: Queries Android `NetworkStatsManager` for tethering data, scans local subnet hostnames, and discovers mDNS / UPnP services when root is unavailable.
- **Local SQLite history**: Stores hourly, daily, monthly, and yearly connection and data usage reports completely offline on the phone.
- **Device friendly names**: Assign custom labels and nicknames to connected devices.
- **Multi-architecture release builds**: arm64-v8a, armeabi-v7a, x86_64, and universal release APKs with SHA-256 checksums.
