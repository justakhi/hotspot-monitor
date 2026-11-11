# Hotspot Monitor

An Android hotspot monitoring app built with Flutter and Kotlin. It works in both non-root and rooted modes, adapting its visible features based on the permissions and root access available on the device.

## Planned features

### Non-root mode
- Hotspot status detection and session timer
- Total tethered data usage per session via Android `NetworkStatsManager` (`UID_TETHERING`)
- Best-effort active device discovery on the hotspot subnet using network probing and mDNS/SSDP hostnames

### Root mode (`su` granted)
- Accurate connected client list from kernel neighbor tables, DHCP leases, and Wi-Fi AP station info (IP, MAC, vendor via OUI lookup, hostname)
- Per-device upload and download data tracking using `iptables` / `nftables` accounting
- Per-device service breakdown (for example YouTube, Instagram, WhatsApp, Netflix) using packet header inspection (DNS queries, TLS SNI hostnames, and IP/port fallback)

## Tech stack
- UI and state management: Flutter (Dart)
- Android system and root bridge: Kotlin via Flutter Platform Channels (`MethodChannel` and `EventChannel`)

## Local development prerequisites
- Flutter SDK
- Android SDK (API 29+ target) and JDK 17+
- Android device (rooted via Magisk or KernelSU to test root features)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
