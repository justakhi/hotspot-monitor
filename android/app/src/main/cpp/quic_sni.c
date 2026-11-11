#include "quic_sni.h"

#include <string.h>

/* --------------------------------------------------------------------------
 * Minimal RFC 6234 / FIPS 180-4 SHA-256 + HMAC-SHA256 + HKDF-Expand-Label
 * -------------------------------------------------------------------------- */

typedef struct {
    uint32_t state[8];
    uint64_t bitlen;
    uint8_t data[64];
    size_t datalen;
} hs_sha256_ctx;

static const uint32_t K256[64] = {
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
    0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
    0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
    0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U
};

#define ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void sha256_transform(hs_sha256_ctx *ctx, const uint8_t block[64]) {
    uint32_t m[64];
    for (int i = 0; i < 16; i++) {
        m[i] = ((uint32_t)block[i * 4] << 24) |
               ((uint32_t)block[i * 4 + 1] << 16) |
               ((uint32_t)block[i * 4 + 2] << 8) |
               ((uint32_t)block[i * 4 + 3]);
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ROR32(m[i - 15], 7) ^ ROR32(m[i - 15], 18) ^ (m[i - 15] >> 3);
        uint32_t s1 = ROR32(m[i - 2], 17) ^ ROR32(m[i - 2], 19) ^ (m[i - 2] >> 10);
        m[i] = m[i - 16] + s0 + m[i - 7] + s1;
    }

    uint32_t a = ctx->state[0], b = ctx->state[1], c = ctx->state[2], d = ctx->state[3];
    uint32_t e = ctx->state[4], f = ctx->state[5], g = ctx->state[6], h = ctx->state[7];

    for (int i = 0; i < 64; i++) {
        uint32_t S1 = ROR32(e, 6) ^ ROR32(e, 11) ^ ROR32(e, 25);
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t temp1 = h + S1 + ch + K256[i] + m[i];
        uint32_t S0 = ROR32(a, 2) ^ ROR32(a, 13) ^ ROR32(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = S0 + maj;

        h = g; g = f; f = e; e = d + temp1;
        d = c; c = b; b = a; a = temp1 + temp2;
    }

    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void sha256_init(hs_sha256_ctx *ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667U;
    ctx->state[1] = 0xbb67ae85U;
    ctx->state[2] = 0x3c6ef372U;
    ctx->state[3] = 0xa54ff53aU;
    ctx->state[4] = 0x510e527fU;
    ctx->state[5] = 0x9b05688cU;
    ctx->state[6] = 0x1f83d9abU;
    ctx->state[7] = 0x5be0cd19U;
}

static void sha256_update(hs_sha256_ctx *ctx, const uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen++] = data[i];
        if (ctx->datalen == 64) {
            sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void sha256_final(hs_sha256_ctx *ctx, uint8_t hash[32]) {
    size_t i = ctx->datalen;
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }

    ctx->bitlen += ctx->datalen * 8;
    for (int b = 0; b < 8; b++) {
        ctx->data[63 - b] = (uint8_t)(ctx->bitlen >> (b * 8));
    }
    sha256_transform(ctx, ctx->data);

    for (int w = 0; w < 8; w++) {
        hash[w * 4] = (uint8_t)(ctx->state[w] >> 24);
        hash[w * 4 + 1] = (uint8_t)(ctx->state[w] >> 16);
        hash[w * 4 + 2] = (uint8_t)(ctx->state[w] >> 8);
        hash[w * 4 + 3] = (uint8_t)(ctx->state[w]);
    }
}

static void hmac_sha256(const uint8_t *key, size_t key_len,
                        const uint8_t *msg, size_t msg_len,
                        uint8_t out[32]) {
    uint8_t k0[64];
    memset(k0, 0, sizeof(k0));
    if (key_len > 64) {
        hs_sha256_ctx c;
        sha256_init(&c);
        sha256_update(&c, key, key_len);
        sha256_final(&c, k0);
    } else if (key_len > 0) {
        memcpy(k0, key, key_len);
    }

    uint8_t ipad[64], opad[64];
    for (int i = 0; i < 64; i++) {
        ipad[i] = (uint8_t)(k0[i] ^ 0x36);
        opad[i] = (uint8_t)(k0[i] ^ 0x5c);
    }

    uint8_t inner[32];
    hs_sha256_ctx ci;
    sha256_init(&ci);
    sha256_update(&ci, ipad, 64);
    sha256_update(&ci, msg, msg_len);
    sha256_final(&ci, inner);

    hs_sha256_ctx co;
    sha256_init(&co);
    sha256_update(&co, opad, 64);
    sha256_update(&co, inner, 32);
    sha256_final(&co, out);
}

static void hkdf_expand_label(const uint8_t secret[32], const char *label,
                              uint8_t *out, size_t out_len) {
    uint8_t info[64];
    size_t l_len = strlen(label);
    if (l_len > 24 || out_len > 32) return;

    size_t pos = 0;
    info[pos++] = (uint8_t)(out_len >> 8);
    info[pos++] = (uint8_t)(out_len & 0xFF);
    info[pos++] = (uint8_t)(6 + l_len);
    memcpy(info + pos, "tls13 ", 6);
    pos += 6;
    memcpy(info + pos, label, l_len);
    pos += l_len;
    info[pos++] = 0x00; /* empty context */
    info[pos++] = 0x01; /* HKDF counter byte */

    uint8_t block[32];
    hmac_sha256(secret, 32, info, pos, block);
    memcpy(out, block, out_len);
}

/* --------------------------------------------------------------------------
 * Minimal FIPS 197 AES-128 Block Cipher (Header Protection + CTR Decryption)
 * -------------------------------------------------------------------------- */

static const uint8_t AES_SBOX[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

static const uint8_t AES_RCON[11] = {
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
};

static uint8_t xtime(uint8_t x) {
    return (uint8_t)((x << 1) ^ (((x >> 7) & 1) * 0x1b));
}

static void aes128_expand_key(const uint8_t key[16], uint8_t rk[176]) {
    memcpy(rk, key, 16);
    for (int i = 4; i < 44; i++) {
        uint8_t temp[4];
        memcpy(temp, rk + (i - 1) * 4, 4);
        if (i % 4 == 0) {
            uint8_t t = temp[0];
            temp[0] = (uint8_t)(AES_SBOX[temp[1]] ^ AES_RCON[i / 4]);
            temp[1] = AES_SBOX[temp[2]];
            temp[2] = AES_SBOX[temp[3]];
            temp[3] = AES_SBOX[t];
        }
        for (int j = 0; j < 4; j++) {
            rk[i * 4 + j] = (uint8_t)(rk[(i - 4) * 4 + j] ^ temp[j]);
        }
    }
}

static void aes128_encrypt_block(const uint8_t rk[176], const uint8_t in[16], uint8_t out[16]) {
    uint8_t s[16];
    for (int i = 0; i < 16; i++) s[i] = (uint8_t)(in[i] ^ rk[i]);

    for (int round = 1; round <= 10; round++) {
        for (int i = 0; i < 16; i++) s[i] = AES_SBOX[s[i]];

        /* ShiftRows (column-major layout) */
        uint8_t t = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t;
        t = s[2]; s[2] = s[10]; s[10] = t;
        t = s[6]; s[6] = s[14]; s[14] = t;
        t = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = t;

        if (round < 10) {
            for (int c = 0; c < 4; c++) {
                uint8_t *col = s + c * 4;
                uint8_t a = col[0], b = col[1], c0 = col[2], d = col[3];
                uint8_t u = (uint8_t)(a ^ b ^ c0 ^ d);
                col[0] ^= (uint8_t)(u ^ xtime((uint8_t)(a ^ b)));
                col[1] ^= (uint8_t)(u ^ xtime((uint8_t)(b ^ c0)));
                col[2] ^= (uint8_t)(u ^ xtime((uint8_t)(c0 ^ d)));
                col[3] ^= (uint8_t)(u ^ xtime((uint8_t)(d ^ a)));
            }
        }
        for (int i = 0; i < 16; i++) s[i] ^= rk[round * 16 + i];
    }
    memcpy(out, s, 16);
}

/* --------------------------------------------------------------------------
 * QUIC Varint + CRYPTO Frame + TLS ClientHello SNI Extraction
 * -------------------------------------------------------------------------- */

static int read_quic_varint(const uint8_t *buf, size_t len, size_t *pos, uint64_t *val) {
    if (*pos >= len) return 0;
    uint8_t first = buf[*pos];
    int prefix = first >> 6;
    size_t width = (size_t)(1 << prefix);
    if (*pos + width > len) return 0;
    uint64_t v = first & 0x3FU;
    for (size_t i = 1; i < width; i++) {
        v = (v << 8) | buf[*pos + i];
    }
    *pos += width;
    *val = v;
    return 1;
}

static int parse_tls_handshake_sni(const uint8_t *hs, size_t len,
                                   char *out_host, size_t out_cap) {
    /* Handshake ClientHello: 0x01, 3-byte len, 2-byte version (0x0303), 32-byte random */
    if (len < 39) return 0;
    if (hs[0] != 0x01) return 0;
    if (hs[4] != 0x03 || (hs[5] != 0x03 && hs[5] != 0x01)) return 0;

    size_t pos = 4 + 2 + 32;
    if (pos >= len) return 0;

    uint8_t sid_len = hs[pos];
    pos += 1 + sid_len;
    if (pos + 2 > len) return 0;

    uint16_t cs_len = (uint16_t)((hs[pos] << 8) | hs[pos + 1]);
    pos += 2 + cs_len;
    if (pos >= len) return 0;

    uint8_t comp_len = hs[pos];
    pos += 1 + comp_len;
    if (pos + 2 > len) return 0;

    uint16_t ext_total = (uint16_t)((hs[pos] << 8) | hs[pos + 1]);
    pos += 2;
    size_t ext_end = pos + ext_total;
    if (ext_end > len) ext_end = len;

    while (pos + 4 <= ext_end) {
        uint16_t ext_type = (uint16_t)((hs[pos] << 8) | hs[pos + 1]);
        uint16_t ext_len = (uint16_t)((hs[pos + 2] << 8) | hs[pos + 3]);
        pos += 4;
        if (pos + ext_len > ext_end) break;

        if (ext_type == 0x0000 && ext_len >= 5) {
            uint16_t list_len = (uint16_t)((hs[pos] << 8) | hs[pos + 1]);
            size_t p = pos + 2;
            size_t list_end = p + list_len;
            if (list_end > pos + ext_len) list_end = pos + ext_len;
            while (p + 3 <= list_end) {
                uint8_t name_type = hs[p];
                uint16_t name_len = (uint16_t)((hs[p + 1] << 8) | hs[p + 2]);
                p += 3;
                if (p + name_len > list_end) break;
                if (name_type == 0 && name_len > 0 && name_len < out_cap) {
                    size_t oi = 0;
                    int has_dot = 0;
                    for (uint16_t i = 0; i < name_len && oi + 1 < out_cap; i++) {
                        unsigned char c = hs[p + i];
                        if (c >= 'A' && c <= 'Z') c = (unsigned char)(c + 32);
                        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.') {
                            if (c == '.') has_dot = 1;
                            out_host[oi++] = (char)c;
                        } else {
                            return 0;
                        }
                    }
                    out_host[oi] = '\0';
                    return (has_dot && oi >= 4) ? 1 : 0;
                }
                p += name_len;
            }
        }
        pos += ext_len;
    }
    return 0;
}

int extract_quic_initial_sni(const uint8_t *udp_payload, size_t len,
                             char *out_host, size_t out_cap) {
    if (len < 64 || out_cap < 8) return 0;

    /* Long Header (bit 7) + Fixed Bit (bit 6) */
    uint8_t first_enc = udp_payload[0];
    if ((first_enc & 0xC0U) != 0xC0U) return 0;

    uint32_t version = ((uint32_t)udp_payload[1] << 24) |
                       ((uint32_t)udp_payload[2] << 16) |
                       ((uint32_t)udp_payload[3] << 8) |
                       ((uint32_t)udp_payload[4]);

    static const uint8_t V1_SALT[20] = {
        0x38, 0x76, 0x2c, 0xf7, 0xf5, 0x59, 0x34, 0xb3, 0x4d, 0x17,
        0x9a, 0xe6, 0xa4, 0xc8, 0x0c, 0xad, 0xcc, 0xbb, 0x7f, 0x0a
    };
    static const uint8_t V2_SALT[20] = {
        0x0d, 0xed, 0xe3, 0xde, 0xf7, 0x00, 0xa6, 0xdb, 0x81, 0x93,
        0x81, 0xbe, 0x6e, 0x26, 0x9d, 0xcb, 0xf9, 0xbd, 0x2e, 0xd9
    };

    const uint8_t *salt = NULL;
    const char *lbl_key = NULL;
    const char *lbl_iv = NULL;
    const char *lbl_hp = NULL;
    uint8_t pkt_type = (uint8_t)((first_enc & 0x30U) >> 4);

    if (version == 0x00000001U && pkt_type == 0x00U) {
        salt = V1_SALT;
        lbl_key = "quic key";
        lbl_iv = "quic iv";
        lbl_hp = "quic hp";
    } else if (version == 0x6b3343cfU && pkt_type == 0x01U) {
        salt = V2_SALT;
        lbl_key = "quicv2 key";
        lbl_iv = "quicv2 iv";
        lbl_hp = "quicv2 hp";
    } else {
        return 0;
    }

    size_t pos = 5;
    if (pos >= len) return 0;
    uint8_t dcid_len = udp_payload[pos++];
    if (dcid_len == 0 || dcid_len > 20 || pos + dcid_len >= len) return 0;
    const uint8_t *dcid = udp_payload + pos;
    pos += dcid_len;

    if (pos >= len) return 0;
    uint8_t scid_len = udp_payload[pos++];
    if (scid_len > 20 || pos + scid_len >= len) return 0;
    pos += scid_len;

    uint64_t token_len = 0;
    if (!read_quic_varint(udp_payload, len, &pos, &token_len)) return 0;
    if (token_len > len || pos + token_len >= len) return 0;
    pos += (size_t)token_len;

    uint64_t pkt_payload_len = 0;
    if (!read_quic_varint(udp_payload, len, &pos, &pkt_payload_len)) return 0;
    size_t pn_offset = pos;
    if (pkt_payload_len < 24 || pkt_payload_len > len - pn_offset) return 0;
    size_t pkt_end = pn_offset + (size_t)pkt_payload_len;
    if (pn_offset + 20 > pkt_end) return 0;

    /* Key derivation from fixed RFC salt + DCID */
    uint8_t initial_secret[32];
    uint8_t client_secret[32];
    uint8_t key[16];
    uint8_t iv[12];
    uint8_t hp[16];
    hmac_sha256(salt, 20, dcid, dcid_len, initial_secret);
    hkdf_expand_label(initial_secret, "client in", client_secret, 32);
    hkdf_expand_label(client_secret, lbl_key, key, 16);
    hkdf_expand_label(client_secret, lbl_iv, iv, 12);
    hkdf_expand_label(client_secret, lbl_hp, hp, 16);

    /* Remove header protection */
    uint8_t hp_rk[176];
    uint8_t mask[16];
    aes128_expand_key(hp, hp_rk);
    aes128_encrypt_block(hp_rk, udp_payload + pn_offset + 4, mask);

    uint8_t first_clear = (uint8_t)(first_enc ^ (mask[0] & 0x0FU));
    size_t pn_len = (size_t)((first_clear & 0x03U) + 1U);
    if (pn_offset + pn_len + 16 >= pkt_end) return 0;

    uint32_t pn = 0;
    for (size_t i = 0; i < pn_len; i++) {
        uint8_t b = (uint8_t)(udp_payload[pn_offset + i] ^ mask[1 + i]);
        pn = (pn << 8) | b;
    }

    /* Decrypt QUIC Initial payload using AES-128-CTR starting at counter J0 + 1 (= 2) */
    size_t ct_offset = pn_offset + pn_len;
    size_t ct_len = pkt_end - ct_offset;
    if (ct_len <= 16) return 0;
    size_t plain_len = ct_len - 16;
    if (plain_len > 1500) plain_len = 1500;

    uint8_t nonce[12];
    memcpy(nonce, iv, 12);
    nonce[8] ^= (uint8_t)(pn >> 24);
    nonce[9] ^= (uint8_t)(pn >> 16);
    nonce[10] ^= (uint8_t)(pn >> 8);
    nonce[11] ^= (uint8_t)(pn);

    uint8_t key_rk[176];
    aes128_expand_key(key, key_rk);

    uint8_t plain[1500];
    uint8_t cb[16];
    memcpy(cb, nonce, 12);
    uint32_t ctr = 2;
    for (size_t off = 0; off < plain_len; off += 16) {
        cb[12] = (uint8_t)(ctr >> 24);
        cb[13] = (uint8_t)(ctr >> 16);
        cb[14] = (uint8_t)(ctr >> 8);
        cb[15] = (uint8_t)(ctr);
        uint8_t ks[16];
        aes128_encrypt_block(key_rk, cb, ks);
        size_t chunk = (plain_len - off < 16) ? (plain_len - off) : 16;
        for (size_t j = 0; j < chunk; j++) {
            plain[off + j] = (uint8_t)(udp_payload[ct_offset + off + j] ^ ks[j]);
        }
        ctr++;
    }

    /* Reassemble CRYPTO frames (type 0x06) across Initial packets (for post-quantum X25519MLKEM768 ClientHello) */
    typedef struct {
        uint8_t used;
        uint8_t dcid_len;
        uint8_t dcid[20];
        uint8_t have_head;
        size_t max_end;
        uint8_t buf[4096];
    } quic_reasm_slot_t;

    static quic_reasm_slot_t g_reasm[48];
    static uint32_t g_reasm_cursor = 0;

    quic_reasm_slot_t *slot = NULL;
    for (int i = 0; i < 48; i++) {
        if (g_reasm[i].used && g_reasm[i].dcid_len == dcid_len &&
            memcmp(g_reasm[i].dcid, dcid, dcid_len) == 0) {
            slot = &g_reasm[i];
            break;
        }
    }
    if (!slot) {
        slot = &g_reasm[g_reasm_cursor++ % 48];
        memset(slot, 0, sizeof(*slot));
        slot->used = 1;
        slot->dcid_len = dcid_len;
        memcpy(slot->dcid, dcid, dcid_len);
    }

    size_t fp = 0;
    int saw_crypto = 0;
    while (fp < plain_len) {
        uint8_t ftype = plain[fp++];
        if (ftype == 0x00) continue; /* PADDING */
        if (ftype == 0x01) continue; /* PING */
        if (ftype == 0x02 || ftype == 0x03) { /* ACK / ACK_ECN */
            uint64_t largest_ack = 0, ack_delay = 0, range_cnt = 0, first_range = 0;
            if (!read_quic_varint(plain, plain_len, &fp, &largest_ack)) break;
            if (!read_quic_varint(plain, plain_len, &fp, &ack_delay)) break;
            if (!read_quic_varint(plain, plain_len, &fp, &range_cnt)) break;
            if (!read_quic_varint(plain, plain_len, &fp, &first_range)) break;
            int ack_ok = 1;
            for (uint64_t r = 0; r < range_cnt; r++) {
                uint64_t gap = 0, ack_len = 0;
                if (!read_quic_varint(plain, plain_len, &fp, &gap) ||
                    !read_quic_varint(plain, plain_len, &fp, &ack_len)) {
                    ack_ok = 0;
                    break;
                }
            }
            if (!ack_ok) break;
            if (ftype == 0x03) {
                uint64_t ect0 = 0, ect1 = 0, ecn_ce = 0;
                if (!read_quic_varint(plain, plain_len, &fp, &ect0) ||
                    !read_quic_varint(plain, plain_len, &fp, &ect1) ||
                    !read_quic_varint(plain, plain_len, &fp, &ecn_ce)) {
                    break;
                }
            }
            continue;
        }
        if (ftype == 0x06) {         /* CRYPTO */
            uint64_t coff = 0, clen = 0;
            if (!read_quic_varint(plain, plain_len, &fp, &coff)) break;
            if (!read_quic_varint(plain, plain_len, &fp, &clen)) break;
            if (clen > plain_len - fp) break;
            saw_crypto = 1;
            if (coff == 0 && clen >= 4 && plain[fp] == 0x01) {
                slot->have_head = 1;
            }
            if (coff < sizeof(slot->buf)) {
                size_t avail = sizeof(slot->buf) - (size_t)coff;
                size_t copy_n = (size_t)clen < avail ? (size_t)clen : avail;
                memcpy(slot->buf + coff, plain + fp, copy_n);
                if ((size_t)coff + copy_n > slot->max_end) {
                    slot->max_end = (size_t)coff + copy_n;
                }
            }
            fp += (size_t)clen;
        } else {
            break;
        }
    }

    if (!saw_crypto || !slot->have_head || slot->max_end < 39) return 0;
    if (parse_tls_handshake_sni(slot->buf, slot->max_end, out_host, out_cap)) {
        slot->used = 0; /* SNI extracted; free slot */
        return 1;
    }
    return 0;
}
