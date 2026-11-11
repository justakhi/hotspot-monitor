package com.justakhi.hotspot_monitor

data class ClassifiedService(
    val serviceId: String,
    val displayName: String,
    val category: String,
    val domain: String
)

object ServiceClassifier {
    private data class DomainRule(
        val suffixes: List<String>,
        val serviceId: String,
        val displayName: String,
        val category: String
    )

    private val rules = listOf(
        // Video streaming (with sub-activity granularity)
        DomainRule(
            listOf("googlevideo.com"),
            "youtube_video", "YouTube · Video Stream", "Video"
        ),
        DomainRule(
            listOf("youtube.com", "youtu.be", "ytimg.com", "yt3.ggpht.com", "youtubei.googleapis.com"),
            "youtube_app", "YouTube · App & Browse", "Video"
        ),
        DomainRule(
            listOf("netflix.com", "nflxvideo.net", "nflxso.net", "nflximg.net", "nflxext.com"),
            "netflix", "Netflix", "Video"
        ),
        DomainRule(
            listOf("primevideo.com", "aiv-cdn.net", "aiv-delivery.net"),
            "prime_video", "Prime Video", "Video"
        ),
        DomainRule(
            listOf("hotstar.com", "disneyplus.com", "dssott.com", "bamgrid.com"),
            "disney_hotstar", "Disney+ / Hotstar", "Video"
        ),
        DomainRule(
            listOf("twitch.tv", "ttvnw.net", "jtvnw.net"),
            "twitch", "Twitch", "Video"
        ),
        DomainRule(
            listOf("vimeo.com", "vimeocdn.com"),
            "vimeo", "Vimeo", "Video"
        ),
        // Social (with sub-activity granularity)
        DomainRule(
            listOf("cdninstagram.com"),
            "instagram_media", "Instagram · Media & Reels", "Social"
        ),
        DomainRule(
            listOf("instagram.com", "ig.me"),
            "instagram_app", "Instagram · Feed & DM", "Social"
        ),
        DomainRule(
            listOf("tiktok.com", "tiktokcdn.com", "tiktokv.com", "musical.ly", "byteoversea.com", "ibytedtos.com"),
            "tiktok", "TikTok", "Social"
        ),
        DomainRule(
            listOf("facebook.com", "fbcdn.net", "fbsbx.com", "fb.com", "messenger.com"),
            "facebook", "Facebook / Messenger", "Social"
        ),
        DomainRule(
            listOf("x.com", "twitter.com", "twimg.com", "t.co"),
            "x_twitter", "X (Twitter)", "Social"
        ),
        DomainRule(
            listOf("sc-cdn.net"),
            "snapchat_media", "Snapchat · Snaps & Media", "Social"
        ),
        DomainRule(
            listOf("snapchat.com", "snap-dev.net"),
            "snapchat", "Snapchat", "Social"
        ),
        DomainRule(
            listOf("reddit.com", "redd.it", "redditmedia.com", "redditstatic.com"),
            "reddit", "Reddit", "Social"
        ),
        DomainRule(
            listOf("linkedin.com", "licdn.com"),
            "linkedin", "LinkedIn", "Social"
        ),
        DomainRule(
            listOf("pinterest.com", "pinimg.com"),
            "pinterest", "Pinterest", "Social"
        ),
        // Messaging & Calls (with WhatsApp sub-activity granularity)
        DomainRule(
            listOf("mmg.whatsapp.net", "cdn.whatsapp.net", "pps.whatsapp.net"),
            "whatsapp_media", "WhatsApp · Media (Img/Audio/Vid)", "Messaging"
        ),
        DomainRule(
            listOf("stun.whatsapp.net", "voice.whatsapp.net"),
            "whatsapp_calls", "WhatsApp · Voice/Video Call", "Messaging"
        ),
        DomainRule(
            listOf("whatsapp.net", "whatsapp.com"),
            "whatsapp_chat", "WhatsApp · Messages", "Messaging"
        ),
        DomainRule(
            listOf("telegram.org", "t.me", "tdesktop.com", "telesco.pe"),
            "telegram", "Telegram", "Messaging"
        ),
        DomainRule(
            listOf("discord.com", "discordapp.com", "discordapp.net", "discord.gg", "discord.media"),
            "discord", "Discord", "Messaging"
        ),
        DomainRule(
            listOf("signal.org", "whispersystems.org"),
            "signal", "Signal", "Messaging"
        ),
        DomainRule(
            listOf("zoom.us", "zoomgov.com"),
            "zoom", "Zoom", "Calls"
        ),
        DomainRule(
            listOf("meet.google.com"),
            "google_meet", "Google Meet", "Calls"
        ),
        DomainRule(
            listOf("teams.microsoft.com", "teams.live.com"),
            "ms_teams", "Microsoft Teams", "Calls"
        ),
        // Music
        DomainRule(
            listOf("spotify.com", "scdn.co", "spotifycdn.com"),
            "spotify", "Spotify", "Music"
        ),
        DomainRule(
            listOf("music.apple.com", "audio-ssl.itunes.apple.com"),
            "apple_music", "Apple Music", "Music"
        ),
        DomainRule(
            listOf("soundcloud.com", "sndcdn.com"),
            "soundcloud", "SoundCloud", "Music"
        ),
        // Gaming
        DomainRule(
            listOf("pubgmobile.com", "igamecj.com", "proximabeta.com"),
            "pubg", "PUBG / BGMI", "Gaming"
        ),
        DomainRule(
            listOf("roblox.com", "rbxcdn.com"),
            "roblox", "Roblox", "Gaming"
        ),
        DomainRule(
            listOf("steampowered.com", "steamstatic.com", "steamcontent.com", "valvesoftware.com"),
            "steam", "Steam", "Gaming"
        ),
        DomainRule(
            listOf("epicgames.com", "unrealengine.com", "fortnite.com"),
            "epic_games", "Epic Games", "Gaming"
        ),
        DomainRule(
            listOf("playstation.com", "playstation.net"),
            "playstation", "PlayStation", "Gaming"
        ),
        DomainRule(
            listOf("xboxlive.com", "xbox.com"),
            "xbox", "Xbox Live", "Gaming"
        ),
        // AI & Dev
        DomainRule(
            listOf("openai.com", "chatgpt.com", "oaistatic.com"),
            "openai", "ChatGPT / OpenAI", "AI & Dev"
        ),
        DomainRule(
            listOf("github.com", "githubusercontent.com", "githubassets.com", "npmjs.org", "pypi.org", "docker.io", "vscode.dev"),
            "github", "Developer Tools (GitHub / Packages)", "AI & Dev"
        ),
        // Carrier Wi-Fi Calling (VoWiFi)
        DomainRule(
            listOf("3gppnetwork.org"),
            "vowifi", "Wi-Fi Calling (VoWiFi)", "Calls"
        ),
        // Cloud, Updates & OS
        DomainRule(
            listOf("play.googleapis.com", "gvt1.com", "gvt2.com", "gvt1-cn.com", "gvt2-cn.com", "android.clients.google.com"),
            "google_play", "Google Play & App Updates", "Cloud & OS"
        ),
        DomainRule(
            listOf("drive.google.com", "docs.google.com", "photos.google.com", "lh3.googleusercontent.com"),
            "google_drive", "Google Drive & Photos", "Cloud & OS"
        ),
        DomainRule(
            listOf("xiaomi.com", "mioffice.cn", "miui.com", "mi.com", "mintkeyboard.com"),
            "xiaomi_system", "Xiaomi / MIUI System Services", "Cloud & OS"
        ),
        DomainRule(
            listOf("samsung.com", "samsungcloud.com", "samsungapps.com", "samsungelectronics.com"),
            "samsung_system", "Samsung System & Galaxy Store", "Cloud & OS"
        ),
        DomainRule(
            listOf("google.com", "google.co.in", "googleapis.com", "gstatic.com", "googleusercontent.com", "1e100.net"),
            "google", "Google Services", "Cloud & OS"
        ),
        // Ads & Mobile Analytics
        DomainRule(
            listOf(
                "doubleclick.net", "googlesyndication.com", "2mdn.net",
                "googletagservices.com", "googletagmanager.com", "adtrafficquality.google",
                "google-analytics.com", "app-measurement.com",
                "inmobi.com", "branch.io", "applovin.com", "unity3d.com", "adjust.com"
            ),
            "ads_analytics", "Ads & App Analytics", "Ads & Analytics"
        ),
        DomainRule(
            listOf("icloud.com", "mzstatic.com", "apple.com", "cdn-apple.com", "aaplimg.com"),
            "apple_services", "Apple / iCloud", "Cloud & OS"
        ),
        DomainRule(
            listOf("windowsupdate.com", "update.microsoft.com", "delivery.mp.microsoft.com", "dsp.mp.microsoft.com", "wdcp.microsoft.com"),
            "windows_update", "Windows Update & Security", "Cloud & OS"
        ),
        DomainRule(
            listOf("onedrive.live.com", "sharepoint.com", "office.com", "office365.com", "sfx.ms", "microsoft.com", "live.com", "msftconnecttest.com"),
            "microsoft", "Microsoft / Windows", "Cloud & OS"
        ),
        DomainRule(
            listOf("cloudflare.com", "cloudflare-dns.com", "1.1.1.1"),
            "cloudflare", "Cloudflare", "Cloud & OS"
        ),
        DomainRule(
            listOf("amazonaws.com", "cloudfront.net"),
            "aws", "Amazon AWS / CloudFront", "Cloud & OS"
        ),
        DomainRule(
            listOf("amazon.com", "amazon.in", "media-amazon.com"),
            "amazon", "Amazon", "Shopping"
        )
    )

    fun classify(hostRaw: String, remoteIp: String, remotePort: Int, proto: Int): ClassifiedService {
        val host = hostRaw.trim().lowercase()
        if (host.isNotEmpty()) {
            classifyMetaSubdomain(host)?.let { return it }

            for (rule in rules) {
                for (suffix in rule.suffixes) {
                    if (host == suffix || host.endsWith(".$suffix")) {
                        return ClassifiedService(
                            serviceId = rule.serviceId,
                            displayName = rule.displayName,
                            category = rule.category,
                            domain = host
                        )
                    }
                }
            }
            val rootDomain = extractRootDomain(host)
            return ClassifiedService(
                serviceId = "domain:$rootDomain",
                displayName = rootDomain,
                category = "Web & Apps",
                domain = host
            )
        }

        classifyByRemoteIp(remoteIp, remotePort)?.let { return it }

        return when {
            remotePort == 53 || remotePort == 5353 -> ClassifiedService(
                "dns", "DNS Lookups", "Network", "$remoteIp:$remotePort"
            )
            proto == 17 && (remotePort == 4500 || remotePort == 500) -> ClassifiedService(
                "vowifi", "Wi-Fi Calling / IPsec (UDP $remotePort)", "Calls", "$remoteIp:$remotePort"
            )
            proto == 17 && remotePort == 443 -> ClassifiedService(
                "quic_udp", "QUIC / HTTP3 (UDP 443)", "Web & Apps", "$remoteIp:443"
            )
            proto == 6 && remotePort == 443 -> ClassifiedService(
                "https_generic", "HTTPS (TCP 443)", "Web & Apps", "$remoteIp:443"
            )
            proto == 6 && remotePort == 80 -> ClassifiedService(
                "http_generic", "HTTP (TCP 80)", "Web & Apps", "$remoteIp:80"
            )
            remotePort == 3478 || remotePort == 19302 -> ClassifiedService(
                "stun_webrtc", "App Call / STUN (UDP $remotePort)", "Calls", "$remoteIp:$remotePort"
            )
            remotePort == 5222 || remotePort == 5228 -> ClassifiedService(
                "push_messaging", "XMPP / Push (TCP $remotePort)", "Messaging", "$remoteIp:$remotePort"
            )
            proto == 1 || proto == 58 -> ClassifiedService(
                "icmp_network", "ICMP / Neighbor Control", "Network", remoteIp
            )
            proto == 17 -> ClassifiedService(
                "udp_other", "Direct UDP Traffic", "Network", "$remoteIp:$remotePort"
            )
            proto == 6 -> ClassifiedService(
                "tcp_other", "Direct TCP Traffic", "Web & Apps", "$remoteIp:$remotePort"
            )
            else -> ClassifiedService(
                "other_traffic", "Other IP Traffic", "Other", remoteIp
            )
        }
    }

    private fun classifyByRemoteIp(rawIp: String, remotePort: Int): ClassifiedService? {
        val ip = unwrapNat64(rawIp.trim().lowercase())
        val isCallPort = remotePort == 3478 || remotePort == 19302
        return when {
            // Google ASN ranges
            ip.startsWith("2001:4860:") || ip.startsWith("2404:6800:") ||
                ip.startsWith("2607:f8b0:") || ip.startsWith("2800:3f0:") ||
                ip.startsWith("2a00:1450:") || ip.startsWith("2c0f:fb50:") ||
                ip.startsWith("142.250.") || ip.startsWith("142.251.") ||
                ip.startsWith("172.217.") || ip.startsWith("172.253.") ||
                ip.startsWith("216.239.") || ip.startsWith("192.178.") ||
                ip.startsWith("74.125.") || ip.startsWith("34.36.") -> ClassifiedService(
                if (isCallPort) "google_webrtc" else "google_ip",
                if (isCallPort) "Google Meet / WebRTC (UDP $remotePort)" else "Google Server (IP)",
                if (isCallPort) "Calls" else "Cloud & OS",
                "$rawIp:$remotePort"
            )
            // Meta ASN ranges + ISP in-network FNA edge caches (:face:b00c:)
            ip.startsWith("2a03:2880:") || ip.contains(":face:b00c:") ||
                ip.startsWith("157.240.") || ip.startsWith("31.13.") ||
                ip.startsWith("69.171.") || ip.startsWith("185.60.216.") -> ClassifiedService(
                if (isCallPort) "meta_call" else "meta_ip",
                if (isCallPort) "Meta Call (WA / IG / FB · UDP $remotePort)" else "Meta / Instagram / Facebook CDN",
                if (isCallPort) "Calls" else "Social",
                "$rawIp:$remotePort"
            )
            // Telegram Data Centers (dedicated Telegram ASN)
            ip.startsWith("2001:b28:") || ip.startsWith("2001:67c:4e8:") ||
                ip.startsWith("91.108.") || ip.startsWith("149.154.16") ||
                ip.startsWith("149.154.17") -> ClassifiedService(
                "telegram", "Telegram (DC IP)", "Messaging", rawIp
            )
            // Cloudflare CDN
            ip.startsWith("2606:4700:") || ip.startsWith("2803:f800:") ||
                ip.startsWith("104.16.") || ip.startsWith("104.17.") ||
                ip.startsWith("104.18.") || ip.startsWith("104.19.") ||
                ip.startsWith("172.64.") || ip.startsWith("172.67.") ||
                ip == "1.1.1.1" || ip == "1.0.0.1" -> ClassifiedService(
                "cloudflare", "Cloudflare (IP)", "Cloud & OS", rawIp
            )
            // Netflix ASN
            ip.startsWith("2607:fb10:") || ip.startsWith("23.246.") ||
                ip.startsWith("45.57.") || ip.startsWith("198.38.") -> ClassifiedService(
                "netflix", "Netflix (IP)", "Video", rawIp
            )
            // Amazon AWS / CloudFront
            ip.startsWith("2600:1f") || ip.startsWith("2600:9000:") ||
                ip.startsWith("3.") || ip.startsWith("13.") ||
                ip.startsWith("18.") || ip.startsWith("52.") ||
                ip.startsWith("54.") -> ClassifiedService(
                "aws", "Amazon AWS (IP)", "Cloud & OS", rawIp
            )
            // Microsoft / Windows / Azure
            ip.startsWith("2603:10") || ip.startsWith("20.") ||
                ip.startsWith("40.") || ip.startsWith("204.79.") -> ClassifiedService(
                "microsoft", "Microsoft (IP)", "Cloud & OS", rawIp
            )
            // GitHub dedicated IPv4 range
            ip.startsWith("140.82.") -> ClassifiedService(
                "github", "Developer Tools (GitHub / Packages)", "AI & Dev", rawIp
            )
            // Apple
            ip.startsWith("2620:149:") || ip.startsWith("17.") -> ClassifiedService(
                "apple_services", "Apple (IP)", "Cloud & OS", rawIp
            )
            else -> null
        }
    }

    private fun classifyMetaSubdomain(host: String): ClassifiedService? {
        val isMetaCdn = host == "fbcdn.net" || host.endsWith(".fbcdn.net") ||
            host == "facebook.com" || host.endsWith(".facebook.com") ||
            host == "messenger.com" || host.endsWith(".messenger.com")
        val isWhatsAppHost = host == "whatsapp.net" || host.endsWith(".whatsapp.net") ||
            host == "whatsapp.com" || host.endsWith(".whatsapp.com")

        if (isWhatsAppHost) {
            return when {
                host.startsWith("stun.") || host.startsWith("voice.") -> ClassifiedService(
                    "whatsapp_calls", "WhatsApp · Voice/Video Call", "Messaging", host
                )
                host.startsWith("mmg.") || host.startsWith("cdn.") ||
                    host.startsWith("pps.") || host.startsWith("media") -> ClassifiedService(
                    "whatsapp_media", "WhatsApp · Media (Img/Audio/Vid)", "Messaging", host
                )
                else -> ClassifiedService(
                    "whatsapp_chat", "WhatsApp · Messages", "Messaging", host
                )
            }
        }

        if (isMetaCdn) {
            if (host.contains("whatsapp")) {
                val isMedia = host.endsWith(".fbcdn.net") || host.contains("media") || host.contains("mmg")
                return ClassifiedService(
                    if (isMedia) "whatsapp_media" else "whatsapp_chat",
                    if (isMedia) "WhatsApp · Media (Img/Audio/Vid)" else "WhatsApp · Messages",
                    "Messaging",
                    host
                )
            }
            if (host.contains("instagram") || host.startsWith("edge-ig") || host.contains("-ig-")) {
                val isMediaCdn = host.endsWith(".fbcdn.net") || host.contains("scontent") || host.contains("video")
                return ClassifiedService(
                    if (isMediaCdn) "instagram_media" else "instagram_app",
                    if (isMediaCdn) "Instagram · Media & Reels" else "Instagram · Feed & DM",
                    "Social",
                    host
                )
            }
            if (host.contains("messenger") || host.startsWith("msgr-") ||
                host.startsWith("chat-e2ee") || host.startsWith("edge-chat")) {
                return ClassifiedService(
                    "facebook_messenger", "Facebook Messenger", "Messaging", host
                )
            }
        }

        return null
    }

    private fun unwrapNat64(ip: String): String {
        // NAT64 prefix 64:ff9b::<hex1>:<hex2> embeds IPv4 in the last 32 bits.
        if (!ip.startsWith("64:ff9b::")) return ip
        val tail = ip.removePrefix("64:ff9b::")
        val parts = tail.split(":")
        if (parts.size != 2) return ip
        val hi = parts[0].toIntOrNull(16) ?: return ip
        val lo = parts[1].toIntOrNull(16) ?: return ip
        return "${(hi ushr 8) and 0xFF}.${hi and 0xFF}.${(lo ushr 8) and 0xFF}.${lo and 0xFF}"
    }

    private fun extractRootDomain(host: String): String {
        val parts = host.split('.').filter { it.isNotEmpty() }
        if (parts.size <= 2) return host
        val secondLast = parts[parts.size - 2]
        val takeCount = if (secondLast.length <= 3 && parts.size >= 3) 3 else 2
        return parts.takeLast(takeCount).joinToString(".")
    }
}
