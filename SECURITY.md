# Security & Privacy Policy

Hotspot Monitor is designed to run **locally and read-only** on your Android device.

## Safety guarantees

- **No system modification:** Even when root (`su`) is granted, Hotspot Monitor does not modify `/system`, `/vendor`, `iptables`/`nftables` firewall rules, system certificates, or Android framework settings.
- **No external telemetry or analytics servers:** All device lists, domain/service breakdowns, learned `IP -> domain` caches (`learned_hosts_v1.tsv`), and usage history (`sqflite` database) stay strictly inside the app's local storage on your phone.
- **Read-only packet header inspection:** The native C probe (`libhs_probe.so`) inspects only unencrypted connection metadata (DNS responses, TLS ClientHello SNI, QUIC Initial SNI, plain HTTP Host headers, DHCP/mDNS identity) to attribute traffic per device and service. Encrypted HTTPS payloads and URL paths remain private.

## Intended use

Hotspot Monitor is provided strictly for educational learning, personal diagnostics, and monitoring networks you own or have explicit permission to administer. Users are responsible for complying with local privacy laws and informing network users where required. The author (`@justakhi`) assumes no responsibility for any misuse.

## Reporting a vulnerability

If you discover a security issue in Hotspot Monitor, please do not post exploit details in public issues before reporting privately. Contact **AP Labs (Akshay Kumar / `@justakhi`)** via email at `contact@techyke.in` ([techyke.in](https://techyke.in)) or Telegram at [`@God_Asura`](https://t.me/God_Asura) with steps to reproduce.
