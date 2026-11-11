/*
 * Hotspot Monitor - Passive AF_PACKET telemetry & SNI/DNS probe (libhs_probe.so)
 * Copyright (c) 2026 AP Labs - Akshay Kumar (@justakhi). All rights reserved.
 * Licensed under PolyForm Noncommercial License 1.0.0. See LICENSE and NOTICE.
 */

#include <arpa/inet.h>
#include <errno.h>
#include <linux/if_arp.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "quic_sni.h"

#define MAX_PACKET_SIZE 2048
#define MAX_HOST_LEN 128
#define CACHE_SIZE 4096
#define BUCKET_SIZE 512
#define TCP_REASM_SLOTS 32
#define TCP_REASM_BUF 4096

typedef struct {
    uint8_t family; /* 4 or 6 */
    uint8_t bytes[16];
} ip_key_t;

typedef struct {
    ip_key_t remote_ip;
    uint8_t client_mac[6];
    uint16_t remote_port;
    char host[MAX_HOST_LEN];
    uint64_t last_used_ms;
} host_cache_entry_t;

typedef struct {
    uint8_t used;
    uint8_t client_mac[6];
    ip_key_t remote_ip;
    uint16_t sport;
    uint16_t dport;
    uint32_t base_seq;
    size_t expected_len;
    size_t max_end;
    uint64_t created_ms;
    uint8_t buf[TCP_REASM_BUF];
} tcp_sni_reasm_t;

typedef struct {
    uint8_t client_mac[6];
    ip_key_t client_ip;
    ip_key_t remote_ip;
    uint16_t remote_port;
    uint8_t proto;
    char host[MAX_HOST_LEN];
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    int used;
} flow_bucket_t;

static volatile sig_atomic_t g_running = 1;
static host_cache_entry_t g_dns_cache[CACHE_SIZE];
static host_cache_entry_t g_sni_cache[CACHE_SIZE];
static tcp_sni_reasm_t g_tcp_reasm[TCP_REASM_SLOTS];
static flow_bucket_t g_buckets[BUCKET_SIZE];
static uint32_t g_dns_cursor = 0;
static uint32_t g_sni_cursor = 0;
static uint32_t g_tcp_reasm_cursor = 0;

static void on_signal(int sig) {
    (void)sig;
    g_running = 0;
}

static uint64_t monotonic_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000ULL);
}

static int ip_key_eq(const ip_key_t *a, const ip_key_t *b) {
    if (a->family != b->family) return 0;
    size_t len = (a->family == 4) ? 4 : 16;
    return memcmp(a->bytes, b->bytes, len) == 0;
}

static void ip_key_to_str(const ip_key_t *k, char *out, size_t cap) {
    if (k->family == 4) {
        inet_ntop(AF_INET, k->bytes, out, (socklen_t)cap);
    } else if (k->family == 6) {
        inet_ntop(AF_INET6, k->bytes, out, (socklen_t)cap);
    } else {
        out[0] = '\0';
    }
}

static void mac_to_str(const uint8_t mac[6], char *out, size_t cap) {
    snprintf(out, cap, "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

static void sanitize_host(const char *src, size_t src_len, char *dst, size_t dst_cap) {
    size_t out = 0;
    for (size_t i = 0; i < src_len && out + 1 < dst_cap; i++) {
        unsigned char c = (unsigned char)src[i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '-') {
            dst[out++] = (char)c;
        } else if (c >= 'A' && c <= 'Z') {
            dst[out++] = (char)(c + 32);
        }
    }
    dst[out] = '\0';
}

static void cache_dns_ip(const ip_key_t *remote_ip, const char *host, uint64_t now_ms) {
    if (host[0] == '\0' || remote_ip->family == 0) return;
    for (int i = 0; i < CACHE_SIZE; i++) {
        if (ip_key_eq(&g_dns_cache[i].remote_ip, remote_ip)) {
            snprintf(g_dns_cache[i].host, MAX_HOST_LEN, "%s", host);
            g_dns_cache[i].last_used_ms = now_ms;
            return;
        }
    }
    uint32_t idx = g_dns_cursor++ % CACHE_SIZE;
    g_dns_cache[idx].remote_ip = *remote_ip;
    memset(g_dns_cache[idx].client_mac, 0, 6);
    g_dns_cache[idx].remote_port = 0;
    snprintf(g_dns_cache[idx].host, MAX_HOST_LEN, "%s", host);
    g_dns_cache[idx].last_used_ms = now_ms;
}

static void cache_sni_flow(const uint8_t client_mac[6], const ip_key_t *remote_ip,
                           uint16_t remote_port, const char *host, uint64_t now_ms) {
    if (host[0] == '\0' || remote_ip->family == 0) return;
    for (int i = 0; i < CACHE_SIZE; i++) {
        if (memcmp(g_sni_cache[i].client_mac, client_mac, 6) == 0 &&
            ip_key_eq(&g_sni_cache[i].remote_ip, remote_ip) &&
            g_sni_cache[i].remote_port == remote_port) {
            snprintf(g_sni_cache[i].host, MAX_HOST_LEN, "%s", host);
            g_sni_cache[i].last_used_ms = now_ms;
            return;
        }
    }
    uint32_t idx = g_sni_cursor++ % CACHE_SIZE;
    memcpy(g_sni_cache[idx].client_mac, client_mac, 6);
    g_sni_cache[idx].remote_ip = *remote_ip;
    g_sni_cache[idx].remote_port = remote_port;
    snprintf(g_sni_cache[idx].host, MAX_HOST_LEN, "%s", host);
    g_sni_cache[idx].last_used_ms = now_ms;
}

static const char *lookup_host(const uint8_t client_mac[6], const ip_key_t *remote_ip,
                               uint16_t remote_port) {
    uint64_t best_ts = 0;
    const char *best = "";
    for (int i = 0; i < CACHE_SIZE; i++) {
        if (memcmp(g_sni_cache[i].client_mac, client_mac, 6) == 0 &&
            ip_key_eq(&g_sni_cache[i].remote_ip, remote_ip) &&
            g_sni_cache[i].remote_port == remote_port &&
            g_sni_cache[i].last_used_ms >= best_ts) {
            best_ts = g_sni_cache[i].last_used_ms;
            best = g_sni_cache[i].host;
        }
    }
    if (best[0] != '\0') return best;

    for (int i = 0; i < CACHE_SIZE; i++) {
        if (ip_key_eq(&g_dns_cache[i].remote_ip, remote_ip) &&
            g_dns_cache[i].last_used_ms >= best_ts) {
            best_ts = g_dns_cache[i].last_used_ms;
            best = g_dns_cache[i].host;
        }
    }
    if (best[0] != '\0') return best;

    for (int i = 0; i < CACHE_SIZE; i++) {
        if (ip_key_eq(&g_sni_cache[i].remote_ip, remote_ip) &&
            g_sni_cache[i].last_used_ms >= best_ts) {
            best_ts = g_sni_cache[i].last_used_ms;
            best = g_sni_cache[i].host;
        }
    }
    return best;
}

static int read_dns_name(const uint8_t *dns, size_t dns_len, size_t offset,
                         char *out, size_t out_cap, size_t *next_offset) {
    size_t pos = offset;
    size_t out_pos = 0;
    int jumped = 0;
    int jumps = 0;
    size_t saved_next = 0;

    while (pos < dns_len && jumps < 10) {
        uint8_t len = dns[pos];
        if (len == 0) {
            if (!jumped) saved_next = pos + 1;
            out[out_pos] = '\0';
            if (next_offset) *next_offset = saved_next;
            return 1;
        }
        if ((len & 0xC0) == 0xC0) {
            if (pos + 1 >= dns_len) return 0;
            uint16_t ptr = (uint16_t)(((len & 0x3F) << 8) | dns[pos + 1]);
            if (ptr >= dns_len) return 0;
            if (!jumped) saved_next = pos + 2;
            jumped = 1;
            jumps++;
            pos = ptr;
            continue;
        }
        if (len > 63 || pos + 1 + len > dns_len) return 0;
        pos++;
        if (out_pos > 0 && out_pos + 1 < out_cap) {
            out[out_pos++] = '.';
        }
        for (uint8_t i = 0; i < len && out_pos + 1 < out_cap; i++) {
            unsigned char c = dns[pos + i];
            if (c >= 'A' && c <= 'Z') c = (unsigned char)(c + 32);
            if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_') {
                out[out_pos++] = (char)c;
            }
        }
        pos += len;
    }
    return 0;
}

static void sanitize_label(const char *src, size_t src_len, char *dst, size_t dst_cap) {
    size_t out = 0;
    for (size_t i = 0; i < src_len && out + 1 < dst_cap; i++) {
        unsigned char c = (unsigned char)src[i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_' || c == ' ') {
            dst[out++] = (char)c;
        }
    }
    dst[out] = '\0';
}

static void parse_dhcp_identity(const uint8_t *dhcp, size_t len, const uint8_t client_mac[6]) {
    if (len < 244) return;
    /* BOOTP magic cookie 99.130.83.99 at offset 236 */
    if (dhcp[236] != 0x63 || dhcp[237] != 0x82 || dhcp[238] != 0x53 || dhcp[239] != 0x63) {
        return;
    }

    char hostname[64];
    char vendor_class[64];
    hostname[0] = '\0';
    vendor_class[0] = '\0';

    size_t pos = 240;
    while (pos < len) {
        uint8_t opt = dhcp[pos++];
        if (opt == 0) continue; /* pad */
        if (opt == 255) break;  /* end */
        if (pos >= len) break;
        uint8_t olen = dhcp[pos++];
        if (pos + olen > len) break;

        if (opt == 12 && olen > 0) {
            sanitize_label((const char *)(dhcp + pos), olen, hostname, sizeof(hostname));
        } else if (opt == 60 && olen > 0) {
            sanitize_label((const char *)(dhcp + pos), olen, vendor_class, sizeof(vendor_class));
        }
        pos += olen;
    }

    if (hostname[0] != '\0' || vendor_class[0] != '\0') {
        char mac_str[20];
        mac_to_str(client_mac, mac_str, sizeof(mac_str));
        printf("H\t%s\t%s\t%s\n", mac_str, hostname, vendor_class);
        fflush(stdout);
    }
}

static void parse_mdns_identity(const uint8_t *dns, size_t dns_len, const uint8_t client_mac[6]) {
    if (dns_len < 12) return;
    uint16_t flags = (uint16_t)((dns[2] << 8) | dns[3]);
    if ((flags & 0x8000) == 0) return; /* only mDNS responses */
    uint16_t qdcount = (uint16_t)((dns[4] << 8) | dns[5]);
    uint16_t ancount = (uint16_t)((dns[6] << 8) | dns[7]);
    if (qdcount > 8 || ancount == 0 || ancount > 24) return;

    size_t pos = 12;
    for (uint16_t q = 0; q < qdcount; q++) {
        char tmp[MAX_HOST_LEN];
        size_t next = 0;
        if (!read_dns_name(dns, dns_len, pos, tmp, sizeof(tmp), &next)) return;
        pos = next + 4;
        if (pos > dns_len) return;
    }

    for (uint16_t a = 0; a < ancount; a++) {
        char rname[MAX_HOST_LEN];
        size_t next = 0;
        if (!read_dns_name(dns, dns_len, pos, rname, sizeof(rname), &next)) return;
        if (next + 10 > dns_len) return;
        uint16_t rtype = (uint16_t)((dns[next] << 8) | dns[next + 1]);
        uint16_t rdlength = (uint16_t)((dns[next + 8] << 8) | dns[next + 9]);
        pos = next + 10;
        if (pos + rdlength > dns_len) return;

        /* Type A(1) or AAAA(28) with <hostname>.local */
        if ((rtype == 1 && rdlength == 4) || (rtype == 28 && rdlength == 16)) {
            size_t rlen = strlen(rname);
            if (rlen > 6 && strcmp(rname + rlen - 6, ".local") == 0) {
                char host[64];
                size_t copy_len = rlen - 6;
                if (copy_len >= sizeof(host)) copy_len = sizeof(host) - 1;
                memcpy(host, rname, copy_len);
                host[copy_len] = '\0';
                /* Ignore service sub-labels like _googlecast._tcp */
                if (host[0] != '\0' && host[0] != '_' && strchr(host, '.') == NULL) {
                    char mac_str[20];
                    mac_to_str(client_mac, mac_str, sizeof(mac_str));
                    printf("H\t%s\t%s\t\n", mac_str, host);
                    fflush(stdout);
                    return;
                }
            }
        }
        pos += rdlength;
    }
}

static void parse_dns_response(const uint8_t *dns, size_t dns_len, uint64_t now_ms) {
    if (dns_len < 12) return;
    uint16_t flags = (uint16_t)((dns[2] << 8) | dns[3]);
    if ((flags & 0x8000) == 0) return;
    uint16_t qdcount = (uint16_t)((dns[4] << 8) | dns[5]);
    uint16_t ancount = (uint16_t)((dns[6] << 8) | dns[7]);
    if (qdcount > 16 || ancount == 0 || ancount > 64) return;

    size_t pos = 12;
    char qname[MAX_HOST_LEN];
    qname[0] = '\0';

    for (uint16_t q = 0; q < qdcount; q++) {
        char tmp[MAX_HOST_LEN];
        size_t next = 0;
        if (!read_dns_name(dns, dns_len, pos, tmp, sizeof(tmp), &next)) return;
        if (q == 0) snprintf(qname, sizeof(qname), "%s", tmp);
        pos = next + 4;
        if (pos > dns_len) return;
    }

    for (uint16_t a = 0; a < ancount; a++) {
        char rname[MAX_HOST_LEN];
        size_t next = 0;
        if (!read_dns_name(dns, dns_len, pos, rname, sizeof(rname), &next)) return;
        if (next + 10 > dns_len) return;
        uint16_t rtype = (uint16_t)((dns[next] << 8) | dns[next + 1]);
        uint16_t rdlength = (uint16_t)((dns[next + 8] << 8) | dns[next + 9]);
        pos = next + 10;
        if (pos + rdlength > dns_len) return;

        if ((rtype == 1 && rdlength == 4) || (rtype == 28 && rdlength == 16)) {
            ip_key_t key;
            memset(&key, 0, sizeof(key));
            key.family = (rtype == 1) ? 4 : 6;
            memcpy(key.bytes, dns + pos, rdlength);
            const char *domain = (qname[0] != '\0') ? qname : rname;
            char clean[MAX_HOST_LEN];
            sanitize_host(domain, strlen(domain), clean, sizeof(clean));
            cache_dns_ip(&key, clean, now_ms);
        }
        pos += rdlength;
    }
}

static int parse_tls_sni(const uint8_t *payload, size_t len,
                         const uint8_t client_mac[6], const ip_key_t *remote_ip,
                         uint16_t remote_port, uint64_t now_ms) {
    if (len < 43) return 0;
    if (payload[0] != 0x16) return 0;
    uint16_t rec_len = (uint16_t)((payload[3] << 8) | payload[4]);
    size_t end = 5 + rec_len;
    if (end > len) end = len;
    if (end < 43) return 0;
    if (payload[5] != 0x01) return 0;

    size_t pos = 5 + 4 + 2 + 32;
    if (pos >= end) return 0;

    uint8_t sid_len = payload[pos];
    pos += 1 + sid_len;
    if (pos + 2 > end) return 0;

    uint16_t cs_len = (uint16_t)((payload[pos] << 8) | payload[pos + 1]);
    pos += 2 + cs_len;
    if (pos >= end) return 0;

    uint8_t comp_len = payload[pos];
    pos += 1 + comp_len;
    if (pos + 2 > end) return 0;

    uint16_t ext_total = (uint16_t)((payload[pos] << 8) | payload[pos + 1]);
    pos += 2;
    size_t ext_end = pos + ext_total;
    if (ext_end > end) ext_end = end;

    while (pos + 4 <= ext_end) {
        uint16_t ext_type = (uint16_t)((payload[pos] << 8) | payload[pos + 1]);
        uint16_t ext_len = (uint16_t)((payload[pos + 2] << 8) | payload[pos + 3]);
        pos += 4;
        if (pos + ext_len > ext_end) break;

        if (ext_type == 0x0000 && ext_len >= 5) {
            uint16_t list_len = (uint16_t)((payload[pos] << 8) | payload[pos + 1]);
            size_t p = pos + 2;
            size_t list_end = p + list_len;
            if (list_end > pos + ext_len) list_end = pos + ext_len;
            while (p + 3 <= list_end) {
                uint8_t name_type = payload[p];
                uint16_t name_len = (uint16_t)((payload[p + 1] << 8) | payload[p + 2]);
                p += 3;
                if (p + name_len > list_end) break;
                if (name_type == 0 && name_len > 0) {
                    char clean[MAX_HOST_LEN];
                    sanitize_host((const char *)(payload + p), name_len, clean, sizeof(clean));
                    if (strchr(clean, '.') != NULL && strlen(clean) >= 4) {
                        cache_sni_flow(client_mac, remote_ip, remote_port, clean, now_ms);
                        return 1;
                    }
                    return 0;
                }
                p += name_len;
            }
        }
        pos += ext_len;
    }
    return 0;
}

static void handle_tcp_tls_sni(const uint8_t *payload, size_t plen,
                               uint32_t tcp_seq, uint16_t sport, uint16_t dport,
                               const uint8_t client_mac[6], const ip_key_t *remote_ip,
                               uint64_t now_ms) {
    /* Fast path: complete ClientHello inside a single TCP segment */
    if (payload[0] == 0x16 && plen >= 6 && payload[5] == 0x01) {
        if (parse_tls_sni(payload, plen, client_mac, remote_ip, dport, now_ms)) {
            return;
        }
        uint16_t rec_len = (uint16_t)((payload[3] << 8) | payload[4]);
        size_t expected = (size_t)5 + rec_len;
        if (expected <= plen) {
            return;
        }
        tcp_sni_reasm_t *slot = NULL;
        for (int i = 0; i < TCP_REASM_SLOTS; i++) {
            if (g_tcp_reasm[i].used &&
                g_tcp_reasm[i].sport == sport &&
                g_tcp_reasm[i].dport == dport &&
                memcmp(g_tcp_reasm[i].client_mac, client_mac, 6) == 0 &&
                ip_key_eq(&g_tcp_reasm[i].remote_ip, remote_ip)) {
                slot = &g_tcp_reasm[i];
                break;
            }
        }
        if (!slot) {
            for (int i = 0; i < TCP_REASM_SLOTS; i++) {
                if (!g_tcp_reasm[i].used || (now_ms - g_tcp_reasm[i].created_ms) > 5000) {
                    slot = &g_tcp_reasm[i];
                    break;
                }
            }
        }
        if (!slot) {
            slot = &g_tcp_reasm[g_tcp_reasm_cursor++ % TCP_REASM_SLOTS];
        }
        memset(slot, 0, sizeof(*slot));
        slot->used = 1;
        memcpy(slot->client_mac, client_mac, 6);
        slot->remote_ip = *remote_ip;
        slot->sport = sport;
        slot->dport = dport;
        slot->base_seq = tcp_seq;
        slot->expected_len = expected < TCP_REASM_BUF ? expected : TCP_REASM_BUF;
        slot->created_ms = now_ms;
        size_t copy_n = plen < TCP_REASM_BUF ? plen : TCP_REASM_BUF;
        memcpy(slot->buf, payload, copy_n);
        slot->max_end = copy_n;
        return;
    }

    /* Continuation TCP segment(s) for a segmented post-quantum ClientHello */
    for (int i = 0; i < TCP_REASM_SLOTS; i++) {
        tcp_sni_reasm_t *slot = &g_tcp_reasm[i];
        if (!slot->used) continue;
        if ((now_ms - slot->created_ms) > 5000) {
            slot->used = 0;
            continue;
        }
        if (slot->sport == sport &&
            slot->dport == dport &&
            memcmp(slot->client_mac, client_mac, 6) == 0 &&
            ip_key_eq(&slot->remote_ip, remote_ip)) {
            uint32_t rel = tcp_seq - slot->base_seq;
            if (rel < TCP_REASM_BUF) {
                size_t avail = TCP_REASM_BUF - (size_t)rel;
                size_t copy_n = plen < avail ? plen : avail;
                memcpy(slot->buf + rel, payload, copy_n);
                if ((size_t)rel + copy_n > slot->max_end) {
                    slot->max_end = (size_t)rel + copy_n;
                }
                int found = parse_tls_sni(slot->buf, slot->max_end,
                                          client_mac, remote_ip, dport, now_ms);
                if (found || slot->max_end >= slot->expected_len) {
                    slot->used = 0;
                }
            }
            return;
        }
    }
}

static void sanitize_url_path(const char *src, size_t src_len, char *dst, size_t dst_cap) {
    size_t out = 0;
    for (size_t i = 0; i < src_len && out + 1 < dst_cap; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c >= 0x21 && c <= 0x7E && c != '\t' && c != '"' && c != '\'' && c != '<' && c != '>') {
            dst[out++] = (char)c;
        } else {
            break;
        }
    }
    dst[out] = '\0';
}

static void parse_http_host(const uint8_t *payload, size_t len,
                            const uint8_t client_mac[6], const ip_key_t *remote_ip,
                            uint16_t remote_port, uint64_t now_ms) {
    size_t limit = len < 768 ? len : 768;
    char req_path[80];
    req_path[0] = '\0';

    /* Extract plain HTTP method path (e.g. GET /video/123 HTTP/1.1) when present */
    if (limit > 8 &&
        ((payload[0] == 'G' && payload[1] == 'E' && payload[2] == 'T' && payload[3] == ' ') ||
         (payload[0] == 'P' && payload[1] == 'O' && payload[2] == 'S' && payload[3] == 'T' && payload[4] == ' ') ||
         (payload[0] == 'H' && payload[1] == 'E' && payload[2] == 'A' && payload[3] == 'D' && payload[4] == ' '))) {
        size_t sp = (payload[3] == ' ') ? 4 : 5;
        if (sp < limit && payload[sp] == '/') {
            size_t path_end = sp;
            while (path_end < limit && payload[path_end] != ' ' && payload[path_end] != '\r' && payload[path_end] != '\n') {
                path_end++;
            }
            if (path_end > sp) {
                sanitize_url_path((const char *)(payload + sp), path_end - sp, req_path, sizeof(req_path));
            }
        }
    }

    for (size_t i = 0; i + 6 < limit; i++) {
        if ((payload[i] == '\n') &&
            (payload[i + 1] == 'H' || payload[i + 1] == 'h') &&
            (payload[i + 2] == 'O' || payload[i + 2] == 'o') &&
            (payload[i + 3] == 'S' || payload[i + 3] == 's') &&
            (payload[i + 4] == 'T' || payload[i + 4] == 't') &&
            payload[i + 5] == ':') {
            size_t start = i + 6;
            while (start < limit && (payload[start] == ' ' || payload[start] == '\t')) start++;
            size_t end = start;
            while (end < limit && payload[end] != '\r' && payload[end] != '\n' && payload[end] != ':') {
                end++;
            }
            if (end > start) {
                char clean_host[64];
                sanitize_host((const char *)(payload + start), end - start, clean_host, sizeof(clean_host));
                if (req_path[0] == '/' && strcmp(req_path, "/") != 0) {
                    char full_url[MAX_HOST_LEN];
                    snprintf(full_url, sizeof(full_url), "http://%s%s", clean_host, req_path);
                    cache_sni_flow(client_mac, remote_ip, remote_port, full_url, now_ms);
                } else {
                    cache_sni_flow(client_mac, remote_ip, remote_port, clean_host, now_ms);
                }
            }
            return;
        }
    }
}

static void flush_buckets(uint64_t now_ms) {
    for (int i = 0; i < BUCKET_SIZE; i++) {
        if (!g_buckets[i].used) continue;
        char mac_str[20];
        char cip[INET6_ADDRSTRLEN];
        char rip[INET6_ADDRSTRLEN];
        mac_to_str(g_buckets[i].client_mac, mac_str, sizeof(mac_str));
        ip_key_to_str(&g_buckets[i].client_ip, cip, sizeof(cip));
        ip_key_to_str(&g_buckets[i].remote_ip, rip, sizeof(rip));

        const char *host = g_buckets[i].host;
        if (host[0] == '\0') {
            host = lookup_host(g_buckets[i].client_mac, &g_buckets[i].remote_ip, g_buckets[i].remote_port);
        }
        printf("D\t%s\t%s\t%s\t%s\t%u\t%u\t%llu\t%llu\n",
               mac_str,
               cip,
               host,
               rip,
               (unsigned)g_buckets[i].remote_port,
               (unsigned)g_buckets[i].proto,
               (unsigned long long)g_buckets[i].rx_bytes,
               (unsigned long long)g_buckets[i].tx_bytes);
        g_buckets[i].used = 0;
    }
    printf("F\t%llu\n", (unsigned long long)now_ms);
    fflush(stdout);
}

static void record_flow(const uint8_t client_mac[6], const ip_key_t *client_ip,
                        const ip_key_t *remote_ip, uint16_t remote_port, uint8_t proto,
                        const char *host, uint64_t rx, uint64_t tx, uint64_t now_ms) {
    for (int i = 0; i < BUCKET_SIZE; i++) {
        if (g_buckets[i].used &&
            memcmp(g_buckets[i].client_mac, client_mac, 6) == 0 &&
            ip_key_eq(&g_buckets[i].remote_ip, remote_ip) &&
            g_buckets[i].remote_port == remote_port &&
            g_buckets[i].proto == proto) {
            g_buckets[i].rx_bytes += rx;
            g_buckets[i].tx_bytes += tx;
            if (g_buckets[i].client_ip.family != 4 && client_ip->family == 4) {
                g_buckets[i].client_ip = *client_ip;
            }
            if (g_buckets[i].host[0] == '\0' && host[0] != '\0') {
                snprintf(g_buckets[i].host, MAX_HOST_LEN, "%s", host);
            }
            return;
        }
    }
    for (int i = 0; i < BUCKET_SIZE; i++) {
        if (!g_buckets[i].used) {
            g_buckets[i].used = 1;
            memcpy(g_buckets[i].client_mac, client_mac, 6);
            g_buckets[i].client_ip = *client_ip;
            g_buckets[i].remote_ip = *remote_ip;
            g_buckets[i].remote_port = remote_port;
            g_buckets[i].proto = proto;
            snprintf(g_buckets[i].host, MAX_HOST_LEN, "%s", host);
            g_buckets[i].rx_bytes = rx;
            g_buckets[i].tx_bytes = tx;
            return;
        }
    }
    flush_buckets(now_ms);
    g_buckets[0].used = 1;
    memcpy(g_buckets[0].client_mac, client_mac, 6);
    g_buckets[0].client_ip = *client_ip;
    g_buckets[0].remote_ip = *remote_ip;
    g_buckets[0].remote_port = remote_port;
    g_buckets[0].proto = proto;
    snprintf(g_buckets[0].host, MAX_HOST_LEN, "%s", host);
    g_buckets[0].rx_bytes = rx;
    g_buckets[0].tx_bytes = tx;
}

static int is_valid_ipv4_remote(uint32_t ip_net) {
    if (ip_net == 0) return 0;
    uint32_t h = ntohl(ip_net);
    if ((h & 0xF0000000U) == 0xE0000000U) return 0; /* multicast */
    if ((h & 0xFF000000U) == 0x7F000000U) return 0; /* loopback */
    if (h == 0xFFFFFFFFU) return 0;
    return 1;
}

static int is_valid_ipv6_remote(const uint8_t ip6[16]) {
    if (ip6[0] == 0xFF) return 0; /* multicast ff00::/8 */
    if (ip6[0] == 0xFE && (ip6[1] & 0xC0) == 0x80) return 0; /* link-local fe80::/10 */
    int all_zero = 1;
    for (int i = 0; i < 16; i++) {
        if (ip6[i] != 0) {
            all_zero = 0;
            break;
        }
    }
    return !all_zero;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <iface> <gateway_ipv4> [prefix_len]\n", argv[0]);
        return 2;
    }

    const char *iface = argv[1];
    unsigned int if_index = if_nametoindex(iface);
    if (if_index == 0) {
        fprintf(stderr, "Interface not found: %s (%s)\n", iface, strerror(errno));
        return 3;
    }

    int sock = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (sock < 0) {
        fprintf(stderr, "AF_PACKET failed: %s\n", strerror(errno));
        return 4;
    }

    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    snprintf(ifr.ifr_name, IFNAMSIZ, "%s", iface);
    if (ioctl(sock, SIOCGIFHWADDR, &ifr) < 0) {
        fprintf(stderr, "SIOCGIFHWADDR(%s) failed: %s\n", iface, strerror(errno));
        close(sock);
        return 5;
    }
    uint8_t ap_mac[6];
    memcpy(ap_mac, ifr.ifr_hwaddr.sa_data, 6);

    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = (int)if_index;
    if (bind(sock, (struct sockaddr *)&sll, sizeof(sll)) < 0) {
        fprintf(stderr, "bind(%s) failed: %s\n", iface, strerror(errno));
        close(sock);
        return 6;
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, on_signal);

    char ap_mac_str[20];
    mac_to_str(ap_mac, ap_mac_str, sizeof(ap_mac_str));
    printf("READY\t%s\t%s\n", iface, ap_mac_str);
    fflush(stdout);

    uint8_t buf[MAX_PACKET_SIZE];
    uint64_t last_flush = monotonic_ms();

    struct pollfd pfds[2];
    pfds[0].fd = sock;
    pfds[0].events = POLLIN;
    pfds[1].fd = STDIN_FILENO;
    pfds[1].events = POLLIN;

    while (g_running) {
        int rc = poll(pfds, 2, 200);
        uint64_t now_ms = monotonic_ms();

        if (rc < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (pfds[1].revents & (POLLHUP | POLLERR | POLLNVAL)) {
            break;
        }
        if (pfds[1].revents & POLLIN) {
            char cmd[32];
            ssize_t r = read(STDIN_FILENO, cmd, sizeof(cmd));
            if (r <= 0) break;
        }

        if (pfds[0].revents & POLLIN) {
            for (int burst = 0; burst < 256; burst++) {
                struct sockaddr_ll rx_sll;
                socklen_t rx_len = sizeof(rx_sll);
                ssize_t n = recvfrom(sock, buf, sizeof(buf), MSG_DONTWAIT,
                                     (struct sockaddr *)&rx_sll, &rx_len);
                if (n <= 0) break;
                if (rx_sll.sll_hatype != ARPHRD_ETHER || (size_t)n < 14) continue;

                const uint8_t *eth_dst = buf;
                const uint8_t *eth_src = buf + 6;
                uint16_t ethertype = (uint16_t)((buf[12] << 8) | buf[13]);
                size_t l2_offset = 14;
                if (ethertype == 0x8100 && (size_t)n >= 18) {
                    ethertype = (uint16_t)((buf[16] << 8) | buf[17]);
                    l2_offset = 18;
                }
                const uint8_t *pkt = buf + l2_offset;
                size_t pkt_cap = (size_t)n - l2_offset;

                int is_upload = 0;
                uint8_t client_mac[6];

                if (memcmp(eth_src, ap_mac, 6) == 0) {
                    if (eth_dst[0] & 0x01) continue; /* multicast/broadcast */
                    memcpy(client_mac, eth_dst, 6);
                    is_upload = 0;
                } else if (memcmp(eth_dst, ap_mac, 6) == 0) {
                    if (eth_src[0] & 0x01) continue;
                    memcpy(client_mac, eth_src, 6);
                    is_upload = 1;
                } else if (!(eth_src[0] & 0x01) && (eth_dst[0] & 0x01)) {
                    /* Client multicast packet (mDNS 224.0.0.251:5353) */
                    if (memcmp(eth_src, ap_mac, 6) == 0) continue;
                    if (ethertype == ETH_P_IP && pkt_cap >= 28 && (pkt[0] >> 4) == 4 && pkt[9] == 17) {
                        size_t ihl = (size_t)(pkt[0] & 0x0F) * 4;
                        if (ihl >= 20 && pkt_cap >= ihl + 8) {
                            const uint8_t *ul4 = pkt + ihl;
                            uint16_t sp = (uint16_t)((ul4[0] << 8) | ul4[1]);
                            uint16_t dp = (uint16_t)((ul4[2] << 8) | ul4[3]);
                            if ((sp == 5353 || dp == 5353) && pkt_cap - ihl > 8) {
                                parse_mdns_identity(ul4 + 8, pkt_cap - ihl - 8, eth_src);
                            }
                        }
                    }
                    continue;
                } else {
                    continue;
                }

                uint8_t proto = 0;
                uint16_t ip_tot_len = 0;
                const uint8_t *l4 = NULL;
                size_t l4_cap = 0;
                ip_key_t client_ip;
                ip_key_t remote_ip;
                memset(&client_ip, 0, sizeof(client_ip));
                memset(&remote_ip, 0, sizeof(remote_ip));

                if (ethertype == ETH_P_IP) {
                    if (pkt_cap < 20 || (pkt[0] >> 4) != 4) continue;
                    size_t ihl = (size_t)(pkt[0] & 0x0F) * 4;
                    if (ihl < 20 || pkt_cap < ihl) continue;
                    ip_tot_len = (uint16_t)((pkt[2] << 8) | pkt[3]);
                    if (ip_tot_len < ihl) ip_tot_len = (uint16_t)pkt_cap;
                    proto = pkt[9];

                    uint32_t s4 = 0, d4 = 0;
                    memcpy(&s4, pkt + 12, 4);
                    memcpy(&d4, pkt + 16, 4);
                    if (!is_valid_ipv4_remote(s4) || !is_valid_ipv4_remote(d4)) continue;

                    client_ip.family = 4;
                    remote_ip.family = 4;
                    if (is_upload) {
                        memcpy(client_ip.bytes, &s4, 4);
                        memcpy(remote_ip.bytes, &d4, 4);
                    } else {
                        memcpy(client_ip.bytes, &d4, 4);
                        memcpy(remote_ip.bytes, &s4, 4);
                    }
                    l4 = pkt + ihl;
                    l4_cap = pkt_cap - ihl;
                } else if (ethertype == ETH_P_IPV6) {
                    if (pkt_cap < 40 || (pkt[0] >> 4) != 6) continue;
                    uint16_t plen = (uint16_t)((pkt[4] << 8) | pkt[5]);
                    ip_tot_len = (uint16_t)(40 + plen);
                    proto = pkt[6];

                    const uint8_t *s6 = pkt + 8;
                    const uint8_t *d6 = pkt + 24;
                    if (!is_valid_ipv6_remote(s6) || !is_valid_ipv6_remote(d6)) continue;

                    client_ip.family = 6;
                    remote_ip.family = 6;
                    if (is_upload) {
                        memcpy(client_ip.bytes, s6, 16);
                        memcpy(remote_ip.bytes, d6, 16);
                    } else {
                        memcpy(client_ip.bytes, d6, 16);
                        memcpy(remote_ip.bytes, s6, 16);
                    }

                    size_t offset = 40;
                    for (int ext = 0; ext < 4 && (proto == 0 || proto == 43 || proto == 60); ext++) {
                        if (offset + 2 > pkt_cap) {
                            offset = pkt_cap;
                            break;
                        }
                        proto = pkt[offset];
                        size_t ext_len = (size_t)(pkt[offset + 1] + 1) * 8;
                        offset += ext_len;
                    }
                    if (offset >= pkt_cap) continue;
                    l4 = pkt + offset;
                    l4_cap = pkt_cap - offset;
                } else {
                    continue;
                }

                uint16_t sport = 0, dport = 0;
                if (proto == 6 && l4_cap >= 20) {
                    sport = (uint16_t)((l4[0] << 8) | l4[1]);
                    dport = (uint16_t)((l4[2] << 8) | l4[3]);
                    uint32_t tcp_seq = ((uint32_t)l4[4] << 24) | ((uint32_t)l4[5] << 16) |
                                       ((uint32_t)l4[6] << 8) | (uint32_t)l4[7];
                    size_t tcp_hlen = (size_t)((l4[12] >> 4) * 4);
                    if (tcp_hlen >= 20 && l4_cap > tcp_hlen) {
                        const uint8_t *payload = l4 + tcp_hlen;
                        size_t plen = l4_cap - tcp_hlen;
                        if (is_upload && (dport == 443 || dport == 4443 || dport == 8443 || dport == 853)) {
                            handle_tcp_tls_sni(payload, plen, tcp_seq, sport, dport,
                                               client_mac, &remote_ip, now_ms);
                        } else if (is_upload && dport == 80) {
                            parse_http_host(payload, plen, client_mac, &remote_ip, dport, now_ms);
                        } else if (!is_upload && sport == 53 && plen > 14) {
                            uint16_t tcp_dns_len = (uint16_t)((payload[0] << 8) | payload[1]);
                            if (tcp_dns_len >= 12 && (size_t)(2 + tcp_dns_len) <= plen) {
                                parse_dns_response(payload + 2, tcp_dns_len, now_ms);
                            }
                        }
                    }
                } else if (proto == 17 && l4_cap >= 8) {
                    sport = (uint16_t)((l4[0] << 8) | l4[1]);
                    dport = (uint16_t)((l4[2] << 8) | l4[3]);
                    if (!is_upload && sport == 53 && l4_cap > 8) {
                        parse_dns_response(l4 + 8, l4_cap - 8, now_ms);
                    } else if (is_upload && (dport == 443 || dport == 4443 || dport == 8443) && l4_cap > 72) {
                        char quic_host[MAX_HOST_LEN];
                        if (extract_quic_initial_sni(l4 + 8, l4_cap - 8, quic_host, sizeof(quic_host))) {
                            cache_sni_flow(client_mac, &remote_ip, dport, quic_host, now_ms);
                        }
                    } else if (is_upload && sport == 68 && dport == 67 && l4_cap > 8) {
                        parse_dhcp_identity(l4 + 8, l4_cap - 8, client_mac);
                    }
                }

                uint16_t remote_port = is_upload ? dport : sport;
                const char *host = lookup_host(client_mac, &remote_ip, remote_port);
                uint64_t rx = is_upload ? 0 : (uint64_t)ip_tot_len;
                uint64_t tx = is_upload ? (uint64_t)ip_tot_len : 0;
                record_flow(client_mac, &client_ip, &remote_ip, remote_port, proto, host, rx, tx, now_ms);
            }
        }

        if (now_ms - last_flush >= 1000) {
            flush_buckets(now_ms);
            last_flush = now_ms;
        }
    }

    flush_buckets(monotonic_ms());
    close(sock);
    return 0;
}
