import '../../../domain/models/service_usage.dart';

class ServiceExplanation {
  const ServiceExplanation({
    required this.summary,
    required this.likelyApps,
    required this.detectionBasis,
  });

  final String summary;
  final String likelyApps;
  final String detectionBasis;
}

class ServiceExplainer {
  static ServiceExplanation explain(ServiceUsage service) {
    final id = service.serviceId;
    if (id == 'youtube_video') {
      return const ServiceExplanation(
        summary:
            'Video stream playback from YouTube CDN servers. High download means someone is watching or buffering videos.',
        likelyApps: 'YouTube app (Android/iOS) or YouTube in a web browser (PC/Phone)',
        detectionBasis: 'Verified via DNS or TLS SNI hostname (googlevideo.com).',
      );
    }
    if (id == 'youtube_app') {
      return const ServiceExplanation(
        summary:
            'YouTube home feed, search, comments, and video thumbnails loading.',
        likelyApps: 'YouTube app or web browser on youtube.com',
        detectionBasis: 'Verified via DNS or TLS SNI hostname (youtube.com / ytimg.com).',
      );
    }
    if (id == 'whatsapp_chat') {
      return const ServiceExplanation(
        summary:
            'WhatsApp text messages, contact/status sync, and background connection keep-alives. Message content is end-to-end encrypted.',
        likelyApps: 'WhatsApp mobile app or WhatsApp Desktop / Web',
        detectionBasis: 'Verified via DNS or TLS SNI hostname (whatsapp.net / whatsapp.com).',
      );
    }
    if (id == 'whatsapp_media') {
      return const ServiceExplanation(
        summary:
            'Photos, voice notes, videos, or documents being sent or downloaded in WhatsApp. Exact file type cannot be separated due to encryption.',
        likelyApps: 'WhatsApp mobile app or WhatsApp Desktop / Web',
        detectionBasis: 'Verified via WhatsApp media CDN domain (mmg.whatsapp.net / cdn.whatsapp.net).',
      );
    }
    if (id == 'whatsapp_calls' || id == 'meta_call') {
      return const ServiceExplanation(
        summary:
            'Live internet voice or video call using Meta real-time calling servers.',
        likelyApps: 'WhatsApp Call, Instagram Call, or Facebook Messenger Call',
        detectionBasis: 'Detected from Meta server IP range combined with STUN/WebRTC call port (UDP 3478/19302).',
      );
    }
    if (id == 'stun_webrtc' || id == 'google_webrtc') {
      return const ServiceExplanation(
        summary:
            'Live audio/video call or real-time peer-to-peer media stream over the internet. Regular SIM phone calls do not use hotspot data.',
        likelyApps:
            'WhatsApp, Google Meet, Instagram, Messenger, Discord, or Zoom calls',
        detectionBasis:
            'Detected from STUN / WebRTC media port (UDP 3478 or 19302). Exact app name is hidden because media packets do not carry domain names after the call starts.',
      );
    }
    if (id == 'vowifi') {
      return const ServiceExplanation(
        summary:
            'Carrier Wi-Fi Calling (VoWiFi), where the connected phone routes regular mobile calls/SMS over your Wi-Fi hotspot.',
        likelyApps: 'Built-in Phone Dialer (VoWiFi / Carrier IMS)',
        detectionBasis: 'Detected via 3GPP ePDG domain (3gppnetwork.org) or IPsec UDP 500/4500.',
      );
    }
    if (id == 'instagram_media' || id == 'instagram_app') {
      return const ServiceExplanation(
        summary:
            'Instagram feed browsing, Reels/Stories video loading, or direct messages (including Meta CDN hosts labeled instagram or edge-ig).',
        likelyApps: 'Instagram app or browser on instagram.com',
        detectionBasis: 'Verified via Instagram CDN, API, or Instagram-specific Meta edge subdomain.',
      );
    }
    if (id == 'facebook_messenger') {
      return const ServiceExplanation(
        summary:
            'Facebook Messenger chat messages, E2EE threads, and attachments.',
        likelyApps: 'Messenger app or Facebook Web chat',
        detectionBasis: 'Verified via Messenger or Meta chat gateway domain (messenger.com / chat-e2ee / msgr).',
      );
    }
    if (id == 'xiaomi_system' || id == 'samsung_system') {
      return const ServiceExplanation(
        summary:
            'Phone manufacturer system services such as MIUI/HyperOS recommendations, keyboard telemetry, cloud sync, or store checks.',
        likelyApps: 'Built-in phone OS system apps & vendor updater',
        detectionBasis: 'Verified via OEM vendor domain (xiaomi.com / mioffice.cn / samsung.com).',
      );
    }
    if (id == 'ads_analytics') {
      return const ServiceExplanation(
        summary:
            'In-app advertisements, ad banners, and app usage measurement running inside apps or websites.',
        likelyApps: 'Mobile apps & browsers loading Google Ads, DoubleClick, InMobi, or App Measurement SDKs',
        detectionBasis: 'Verified via ad-network and mobile attribution domain.',
      );
    }
    if (id == 'telegram') {
      return const ServiceExplanation(
        summary:
            'Telegram chats, channels, media downloads, or calls.',
        likelyApps: 'Telegram mobile app, Telegram Desktop, or web.telegram.org',
        detectionBasis: 'Verified via Telegram domain or dedicated Telegram data center IP.',
      );
    }
    if (id == 'snapchat' || id == 'snapchat_media') {
      return const ServiceExplanation(
        summary:
            'Snapchat Snaps, Stories, Spotlight videos, and chat sync.',
        likelyApps: 'Snapchat mobile app',
        detectionBasis: 'Verified via Snapchat domain (snapchat.com / sc-cdn.net).',
      );
    }
    if (id == 'google_ip' || id == 'google') {
      return const ServiceExplanation(
          summary:
              'Encrypted traffic to Google servers. Could be Chrome browsing, YouTube, Google Drive, Play Store, or Gmail.',
          likelyApps:
              'Google Chrome, YouTube, Google Play Store, Google Drive, or Android system sync',
          detectionBasis:
              'Matched Google server IP range (or *.1e100.net PTR). Because the connection started earlier or uses encrypted QUIC/DoH, the specific Google app subdomain was not visible.',
      );
    }
    if (id == 'google_play') {
      return const ServiceExplanation(
        summary: 'Android app downloads, updates, or Google Play Store browsing.',
        likelyApps: 'Google Play Store / Android Package Installer',
        detectionBasis: 'Verified via Google Play download/API domain.',
      );
    }
    if (id == 'google_drive') {
      return const ServiceExplanation(
        summary: 'Files, documents, or photos syncing with Google Drive or Google Photos.',
        likelyApps: 'Google Drive, Google Photos, or browser',
        detectionBasis: 'Verified via Google Drive/Photos domain.',
      );
    }
    if (id == 'meta_ip' || id == 'facebook') {
      return const ServiceExplanation(
        summary:
            'Encrypted traffic to Meta servers (Facebook, Instagram, or WhatsApp).',
        likelyApps: 'Facebook, Instagram, Messenger, or WhatsApp',
        detectionBasis:
            'Matched Meta server IP range or domain. When only the IP is shown, the connection was already open before capture started.',
      );
    }
    if (id == 'windows_update') {
      return const ServiceExplanation(
        summary: 'Windows OS updates, Microsoft Store downloads, or Defender definitions.',
        likelyApps: 'Windows Update / Microsoft Store (PC)',
        detectionBasis: 'Verified via Windows Update domain.',
      );
    }
    if (id == 'microsoft') {
      return const ServiceExplanation(
        summary: 'Microsoft account sync, OneDrive, Office, Edge, or Windows background services.',
        likelyApps: 'Microsoft Edge, Office 365, OneDrive, or Windows OS',
        detectionBasis: 'Verified via Microsoft domain or IP range.',
      );
    }
    if (id == 'github') {
      return const ServiceExplanation(
        summary: 'Code repositories, package downloads, or developer tool traffic.',
        likelyApps: 'Git, VS Code, npm, Python pip, Docker, or browser on GitHub',
        detectionBasis: 'Verified via developer platform domain.',
      );
    }
    if (id == 'dns') {
      return const ServiceExplanation(
        summary:
            'Small address-book lookups that turn website names (like youtube.com) into server IP addresses.',
        likelyApps: 'System network resolver on the connected device',
        detectionBasis: 'UDP/TCP port 53 traffic.',
      );
    }
    if (id == 'icmp_network') {
      return const ServiceExplanation(
        summary:
            'Tiny background ping and Wi-Fi neighbor discovery packets used to keep the connection alive.',
        likelyApps: 'Operating system network stack',
        detectionBasis: 'ICMP / ICMPv6 control packets.',
      );
    }
    if (id == 'quic_udp' || id == 'https_generic') {
      return const ServiceExplanation(
        summary:
            'Encrypted web or app traffic where no domain name was captured (often connections opened before monitoring started, or encrypted DoH/ECH). Check the server IPs below.',
        likelyApps: 'Web browser or background mobile/desktop app',
        detectionBasis:
            'Detected on encrypted port 443 (TCP/HTTPS or UDP/QUIC) without a visible DNS/SNI header.',
      );
    }
    if (id == 'udp_other' || id == 'tcp_other' || id == 'other_traffic') {
      return const ServiceExplanation(
        summary:
            'Direct network traffic to specific IP addresses and ports. Check the Destinations list below to see the exact servers.',
        likelyApps: 'Game, VPN, calling app, local file transfer, or background service',
        detectionBasis:
            'Measured directly from IP packet headers without a matched domain name.',
      );
    }
    if (id.startsWith('domain:')) {
      final domain = service.displayName;
      return ServiceExplanation(
        summary:
            'Direct traffic to $domain servers. Any app or web browser on the connected device communicating with $domain is counted here.',
        likelyApps: 'App or web browser visiting $domain',
        detectionBasis: 'Verified from DNS lookup, TLS SNI, or HTTP Host header.',
      );
    }

    return ServiceExplanation(
      summary:
          'Traffic grouped under ${service.displayName} (${service.category}). Check the destinations below to see the exact servers used.',
      likelyApps: '${service.displayName} app or web browser',
      detectionBasis: 'Matched from captured domain or provider network range.',
    );
  }

  static String directionSummary(int downloadBytes, int uploadBytes) {
    final total = downloadBytes + uploadBytes;
    if (total <= 0) return 'No data transferred yet.';
    final downPct = (downloadBytes / total) * 100;
    if (downPct >= 75) {
      return 'Mostly downloading (${downPct.round()}% received): typical for watching video, loading feeds, or downloading files.';
    }
    if (downPct <= 25) {
      return 'Mostly uploading (${(100 - downPct).round()}% sent): typical for sending media, backups, screen sharing, or outgoing video.';
    }
    return 'Balanced two-way traffic (${downPct.round()}% down / ${(100 - downPct).round()}% up): typical for live calls, chat, or interactive browsing.';
  }

  static String? launchableUrl(String rawEndpoint) {
    final trimmed = rawEndpoint.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    // Strip optional :port only if it's a hostname, not an IPv4/IPv6 literal.
    final cleanHost = trimmed.contains('[') ? '' : trimmed.split(':').first;
    final lower = cleanHost.toLowerCase();
    if (lower.isEmpty ||
        !lower.contains('.') ||
        lower.contains(':') ||
        RegExp(r'^[\d.]+$').hasMatch(lower)) {
      return null;
    }
    return 'https://$lower';
  }

  static String? explainEndpoint(String endpoint) {
    final lower = endpoint.toLowerCase();
    if (lower.startsWith('http://')) {
      return 'Unencrypted HTTP URL path captured from packet header';
    }
    if (lower.contains('googlevideo.com')) {
      return 'YouTube / Google Video media chunk CDN (audio & video stream)';
    }
    if (lower.contains('ytimg.com') || lower.contains('ggpht.com')) {
      return 'Video thumbnails and channel profile images';
    }
    if (lower.contains('youtubei.googleapis.com') || lower.contains('youtube.com')) {
      return 'YouTube feed, search, comments, and playback control API';
    }
    if (lower.contains(':face:b00c:') || lower.contains('2a03:2880:')) {
      return 'Meta edge server (Instagram, Facebook, or WhatsApp CDN)';
    }
    if (lower.contains('edge-ig') || lower.contains('-ig-')) {
      return 'Instagram real-time feed / Direct Messaging gateway on Meta servers';
    }
    if (lower.contains('whatsapp-chatd')) {
      return 'WhatsApp persistent chat messaging socket on Meta servers';
    }
    if (lower.contains('instagram') || lower.contains('cdninstagram.com') || lower.contains('scontent')) {
      return 'Instagram / Meta photos, Reels video, and Stories CDN';
    }
    if (lower.contains('mmg.whatsapp.net') || lower.contains('cdn.whatsapp.net') || lower.contains('media.')) {
      return 'WhatsApp encrypted photo, voice note, video, or document download/upload';
    }
    if (lower.contains('doubleclick') || lower.contains('googlesyndication') || lower.contains('inmobi') || lower.contains('app-measurement')) {
      return 'In-app ad loading or analytics measurement';
    }
    if (lower.contains('events.data.microsoft')) {
      return 'Windows / Microsoft telemetry & diagnostics upload';
    }
    if (lower.contains('stun.')) {
      return 'Live call connection setup (STUN / WebRTC)';
    }
    if (lower.contains('windowsupdate') || lower.contains('delivery.mp.microsoft')) {
      return 'Windows OS / Defender update package server';
    }
    if (lower.contains('gvt1.com') || lower.contains('play.googleapis.com')) {
      return 'Google Play Store APK download or app update';
    }
    if (lower.contains(':443')) {
      return 'Encrypted HTTPS / QUIC server IP (port 443)';
    }
    if (lower.contains(':3478') || lower.contains(':19302')) {
      return 'Real-time voice/video call media relay (UDP STUN/WebRTC)';
    }
    return null;
  }
}
