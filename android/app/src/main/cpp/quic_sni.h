#ifndef HS_QUIC_SNI_H
#define HS_QUIC_SNI_H

#include <stddef.h>
#include <stdint.h>

/*
 * Extracts TLS SNI hostname from a client-to-server QUIC Initial packet
 * (supports RFC 9001 QUIC v1 and RFC 9369 QUIC v2) into out_host.
 * Returns 1 if a valid SNI hostname was extracted, 0 otherwise.
 */
int extract_quic_initial_sni(const uint8_t *udp_payload, size_t len,
                             char *out_host, size_t out_cap);

#endif
