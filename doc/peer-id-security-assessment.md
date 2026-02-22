# Peer ID Theft Security Assessment

Last updated: 2026-02-21

## Summary

D-LAN operates on a trusted LAN model with no cryptographic proof-of-identity for peer IDs.
A peer can claim any peer ID in its `IMAlive` broadcasts. This document assesses the threat,
impact, and mitigation options.

**Risk acceptance decision**: Accept for v1.x. Track as a v2.0 protocol enhancement. See
[Mitigation Roadmap](#mitigation-roadmap) below.

---

## Threat Model

### Asset

Each D-LAN peer has a persistent **Peer ID** — a 20-byte (SHA-1 sized) random value generated
once and stored in settings. The Peer ID identifies the peer across all protocol messages
(IMAlive, GetEntries, GetHashes, GetChunk, Chat).

### Attacker Capability

An attacker on the same LAN segment can:

1. Observe IMAlive UDP multicast broadcasts from any peer.
2. Extract the `peer_id` field from observed messages.
3. Craft IMAlive messages claiming the victim's `peer_id`.

### Attack Scenario

```
Victim  (ID=V, address=192.168.1.10)
Attacker (own ID=A, address=192.168.1.99)

1. Attacker observes: IMAlive{peer_id=V, ip=192.168.1.10, ...}
2. Attacker broadcasts: IMAlive{peer_id=V, ip=192.168.1.99, ...}
3. Other peers now see two entries for peer_id=V with conflicting IPs.
4. Downloads/uploads targeting V may be redirected to Attacker.
```

### Impact Assessment

| Factor | Assessment |
|--------|-----------|
| **Network scope** | LAN-only (multicast TTL=1 by default; attacks require local LAN presence) |
| **Attacker prerequisite** | Must be on the same LAN segment |
| **Confidentiality impact** | **Medium** — attacker could receive chunks/files intended for the victim |
| **Integrity impact** | **Low** — attacker cannot forge signed content; they can only redirect transfers |
| **Availability impact** | **Low** — victim peer still broadcasts; duplicate ID confusion is transient |
| **Authentication impact** | **High** — peer identity is entirely unauthenticated |

### LAN Trust Model Context

D-LAN is explicitly designed for trusted LAN environments (home, office). The security wiki
acknowledges this vulnerability without mitigation. In a trusted LAN, the attack requires a
malicious insider. For home and small-office use cases, this is generally an acceptable risk.

---

## Current State

- **Peer ID generation (post H2)**: `QRandomGenerator::global()` (OS CSPRNG). IDs are now
  cryptographically random and cannot be predicted from observations.
- **IMAlive rate-limiting (H8)**: Excessive IMAlive floods from a single IP are dropped and
  temporarily banned. This limits the rate at which a spoofing attacker can disrupt discovery.
- **No proof-of-identity**: There is no mechanism for a peer to prove it owns its claimed ID.

The H2 and H8 mitigations reduce some attack surface (ID prediction, flood) but do not address
the core identity spoofing vulnerability.

---

## Mitigation Options

### Option A: HMAC-signed IMAlive (Lightweight, Symmetric)

**Mechanism**: On first launch, each peer generates a random 256-bit long-term secret key stored
alongside the peer ID. Each IMAlive message includes an HMAC-SHA256 of the message body keyed
with this secret. Receiving peers cache the HMAC key received in the first authentic IMAlive
from each peer ID, and verify subsequent messages.

**Protocol change**: Adds one field to `IMAlive` (`auth_token: bytes`). Proto2 optional — wire
compatible with old clients (they ignore unknown fields).

**Limitation**: Does not protect against a first-message attack where the attacker broadcasts
before the victim. The key is self-certified (not CA-signed).

**Effort**: Low–medium (proto change + key storage + HMAC on send/verify on recv).

---

### Option B: Ed25519 Challenge/Response (Strong, Asymmetric)

**Mechanism**: Each peer generates a persistent Ed25519 keypair. The `peer_id` is derived as
`SHA-256(public_key)` (breaking current peer ID format — **protocol break**). A new TCP handshake
step sends a nonce challenge; the responder signs it with its private key.

**Protocol change**: New `peer_id` format (32 bytes); new `PeerChallenge`/`PeerChallengeReply`
TCP messages. **Requires protocol version bump.**

**Strength**: Cryptographically strong proof-of-identity. Standard approach used by modern P2P
systems (e.g., BitTorrent DHT with Ed25519 node IDs).

**Effort**: High. New keypair lifecycle, key storage, protocol version negotiation.

---

### Option C: Rely on Transport-Layer Authentication (TLS/DTLS)

**Mechanism**: Wrap all TCP connections in TLS with self-signed per-peer certificates. Peer ID
becomes the certificate fingerprint. DTLS for UDP multicast (complex).

**Limitation**: UDP multicast (IMAlive, Find, FindResult) cannot practically use DTLS in
multicast mode. TLS adds significant handshake overhead for short-lived chunk connections.

**Effort**: Very high. Not recommended for v1.x.

---

## Mitigation Roadmap

| Phase | Action | Effort | Protocol Break |
|-------|--------|--------|----------------|
| v1.x (current) | Accept risk; document threat; H8 rate-limit mitigates flood | — | No |
| v1.x (optional) | Implement Option A (HMAC-signed IMAlive) | Low–medium | No (additive field) |
| v2.0 | Implement Option B (Ed25519 keypair, new peer_id format) | High | Yes |

**Recommendation**: Implement Option A as a non-breaking incremental improvement in a v1.x
patch. Plan Option B for the v2.0 protocol redesign alongside the SHA-1 → SHA-256 chunk hash
upgrade (see roadmap item #3).

---

## References

- D-LAN Security wiki: https://github.com/oct8l/D-LAN/wiki/Security
- `application/Core/NetworkListener/priv/UDPListener.cpp` — IMAlive handling
- `application/Protos/core_protocol.proto` — IMAlive message definition
- `application/Common/Hash.cpp:204` — Peer ID generation (`Hash::rand()` using CSPRNG)
