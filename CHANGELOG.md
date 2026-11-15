# Changelog

All notable changes to Hotspot Monitor are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - Unreleased

### Added
- **Hotspot data quota and alerts**: Set session data budgets (500 MB, 1 GB, 2 GB, 5 GB, or custom) with proactive warning states at 80% and overage alerts. Works in both root and non-root modes.
- **Per-device internet access control (root mode)**: Drop or allow client device internet traffic in memory via standard Linux `iptables` rules in RAM without writing to system partitions or altering phone connectivity.
- **Per-device data limits (root mode)**: Set individual byte quotas for specific connected devices with optional auto-blocking when their limit is reached.
- **In-app update checker**: Checks GitHub Releases on startup and in settings. Displays a popup with release notes and a direct download link when a new version is published.
- **Changelog tracking**: Structured changelog published alongside every release build.

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
