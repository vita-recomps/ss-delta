# 11 — Online multiplayer without a VPN (overlay first, Play Online later)

Plan written 2026-11-27, revised the same day after a review against the
fork source (`3c2ae20c`) and the import inventory. Today ss-delta plays
online through Ad Hoc Play over a third-party VPN (Tailscale, ZeroTier or
Radmin VPN) with the host's address entered by hand
([ONLINE-PLAY](ONLINE-PLAY.md)), while Librom's **Play Online** menu ends
as cancelled (`cfg.offline = true`).

This plan removes the VPN requirement in two decoupled stages inspired by
[Project Nativ](https://github.com/TheLostPantheon/nativ)'s networking
stack (read at `1707e505`, GPL-2.0-or-later):

1. **Part 1 — P2P overlay under Ad Hoc Play (L, ~12–20 sessions):**
   carry Ad Hoc Play traffic over an encrypted, NAT-traversing P2P
   overlay (LAN multicast, BitTorrent DHT rendezvous, STUN/UPnP hole
   punching, relay fallback). No new firmware modules and no extra build
   time for players. Gated by a latency spike (16a.0) that runs before
   any overlay code is written.
2. **Part 2 — Full Play Online via NP Matching2 (L–XL, ~15–25 sessions,
   optional later stage):** layer Nativ's Matching2 service and LLE
   firmware modules (`np_matching2`, `librudp`, `libssl`, `np_common`) on
   top of Part 1's overlay without rewriting the transport layer,
   restoring the game's own **Play Online** menu (room search, in-game
   room passwords, lobby chat, kick, host handover, and `SceLibRudp` WAN
   transport).

Claims not yet checked against Soul Sacrifice Delta's binary, firmware
3.74 or a running build are marked **hypothesis**.

## Prerequisites

* The 0.6.1 items that touch the same code are closed first: audio
  during an Ad Hoc pause (fork `app/src/session_controller.cpp`) and
  `Queue::abort()` without the mutex ([03-plan](03-plan.md), Next release
  0.6.1). Part 1 relies on socket abort and the Ad Hoc pause behaving.
* 16a.0 (the latency spike, scheduled in the 0.6.1 checklist) passes, or
  an eboot patch for the latency limit is found.

## Why stage it overlay-first

| | Part 1: overlay under Ad Hoc Play | Part 2: full Play Online (Matching2 + RUDP) |
|---|---|---|
| **Player experience** | Ad Hoc Play without a VPN, joined by room code; US↔EU cross-play, Blank Pages, 4-player quests | The game's **Play Online** menu: room search, in-game passwords, lobby chat, kick, host handover |
| **Extra firmware modules** | None (stays at the current 10 modules) | +4–6 modules (~455 KB+ vs. 14 KB for `adhoc_matching`), a one-time rebuild and a longer setup on Android |
| **Attack surface** | Small: the overlay decrypts and validates packets; the guest runs only the 14 KB `adhoc_matching` | Larger: Sony's `libssl`, `np_matching2` and `librudp` parse untrusted remote frames in guest memory |
| **Rework when moving to Part 2** | None if the design invariants below are kept | Builds on Part 1's overlay, virtual IPs and vport mux |

## Licence boundary

Project Nativ is **GPL-2.0-or-later**, the same licence as our Vita3K
fork (`third_party/vita3k`). Any code adapted from Nativ goes **only**
into `third_party/vita3k` (or a separate GPL relay project, 16a.2) with
attribution and GPL headers preserved, never into MIT-licensed
`third_party/recomp` or this repository's top-level scripts. Ideas,
wire-protocol specs and configuration designs have no restriction.
Monocypher (crypto) is CC0 / BSD-2-Clause.

---

## Design invariants (keep Part 1 compatible with Part 2)

1. **One WAN UDP port, vport carried in the overlay framing.** Vita3K's
   `P2PSocket` (`vita3k/net/src/p2psocket.cpp`) maps a guest
   `(port, vport)` to a host UDP port `port + vport` (`3658 + vport` for
   the Ad Hoc port). Over the internet that gives every virtual port its
   own NAT mapping and breaks STUN and hole punching. The overlay sends
   all peer traffic through a single WAN socket and carries `vport` in
   its header.
2. **Loopback bridge, not a socket replacement.** `Epoll::wait`
   (`vita3k/net/src/epoll.cpp`) runs `select()` on each `PosixSocket`'s
   host fd, and receive timeouts (`SO_RCVTIMEO`, used by the `SceNetCtl`
   peer thread), blocking and non-blocking I/O and `sceNetSocketAbort`
   all rely on real host sockets. So in `online` mode guest P2P sockets
   keep real host UDP sockets, bound on loopback, and an overlay thread
   forwards between them and the WAN socket. `P2PSocket` only translates
   addresses (virtual IP + vport ↔ loopback port). Epoll, timeouts and
   abort stay unchanged. macOS configures only `127.0.0.1` by default,
   so the bridge maps by port on `127.0.0.1`, not by `127.0.0.N`.
3. **Unique, session-wide virtual IPs in `198.18.0.0/15`.** Each node
   gets one address (RFC 2544 benchmark space, as in Nativ) that every
   peer sees the same way: derived from the node's public key, with a
   deterministic tie-break on collision. A per-node local view (or every
   node calling itself `198.18.0.1`) breaks the `SceNetCtl` peer
   thread's self-filter (`fromAddr != netAddr`) and any address the
   guest carries in a payload: `SceNetCtlAdhocPeerInfo.addr`, and
   possibly `adhoc_matching`'s packets (**hypothesis**, check with
   `net_trace`). The overlay also defines a virtual broadcast address
   (`198.19.255.255`) that `is_lan_broadcast` recognises and the bridge
   fans out to the session's peers. `local` (`127.0.0.N`) and `lan`
   paths stay untouched, so existing Ad Hoc Play and utakata don't
   regress.
4. **Guest-agnostic overlay library.** Transport and discovery live in
   `third_party/vita3k/vita3k/net/online/` as plain C/C++ with **no**
   `EmuEnvState` or guest-memory dependencies. Part 1 adapts it into
   `P2PSocket` and `SceNetCtl`; Part 2 plugs `m2_server` / `m2_proxy`
   into the same API.
5. **Versioned, namespaced wire framing and DHT topics.** Overlay
   headers, handshakes and DHT infohash derivations include a protocol
   version, the game ID (`ss-delta`, `utakata`: the fork is shared), a
   game compatibility version (players must run compatible releases, as
   ONLINE-PLAY already requires) and a service tag (`adhoc` vs. `m2`).
   Part 1 and Part 2 clients, and both games, can share DHT and relay
   nodes without colliding. US and EU share a compatibility group.
6. **Forward-compatible settings.** `[multiplayer]` keys stay generic
   (`network`, `room_code`, `relay`, `upnp`, `online_id`), so Play Online
   extends `ss-delta.ini` later without breaking existing configs.

---

## Part 1 — P2P overlay under Ad Hoc Play (L)

### Architecture

```text
Game (eboot + adhoc_matching.suprx)
  └─ SceNet / P2PSocket + Epoll + SceNetCtl (adhoc peer table)
       ├─ network = local  ──► 127.0.0.1..4 (existing)
       ├─ network = lan    ──► host UDP + broadcast / VPN peers (existing)
       └─ network = online ──► host UDP on 127.0.0.1 (one port per guest socket)
                                 └─ loopback bridge ◄─► vita3k/net/online/ (new, GPL-2.0-or-later)
                                      ├─ overlay   (session virtual IPs, vport mux, hole punch, reliable stream, relay client)
                                      ├─ crypto    (X25519 handshake, XChaCha20-Poly1305 via Monocypher)
                                      ├─ discovery (LAN multicast)
                                      ├─ dht       (BitTorrent Mainline DHT rendezvous)
                                      └─ stun/upnp (external endpoint discovery, opt-in port mapping)
```

### Rooms

Ad Hoc rooms hold four players, so Part 1 joins players by **room
code** (`[multiplayer] room_code`) rather than through one public lobby.
In a single worldwide topic every node would receive every other node's
once-a-second Ad Hoc broadcasts and hole-punch each of them (O(N²)),
Search for Room would fill with strangers' rooms, and every player's IP
address would be published.

* The host generates a random code in the Multiplayer menu (high
  entropy, e.g. `ABCD-EFGH-JKLM`, 60+ bits) and shares it. Guests type
  it in.
* The code goes through a KDF into both the DHT infohash and the
  handshake pre-shared key. The infohash is public, so a short
  hand-picked code could be brute-forced offline. Generated codes are
  the default. A typed code below a minimum length is refused.
* A public lobby (matchmaking by region, with a peer cap) is deferred
  until the room-code path works. It would need its own scaling design.

### Implementation steps (Phase 16a)

* **16a.0 Latency and loss spike (1–2 sessions, before any overlay
  code):** on real hardware Ad Hoc needed an eboot patch to lift a
  ~24 ms ping limit for XLink Kai ([01-research](01-research.md#other)).
  No WAN latency measurement of ss-delta's Ad Hoc Play is on record.
  * Use the existing `lan` + VPN path (or two local copies) with added
    delay and loss: clumsy on Windows, `tc netem` on Linux. Test 50,
    100 and 200 ms RTT and 1–5 % loss through room creation, joining and
    a full quest, including Blank Pages and 4 players.
  * Look for the XLink Kai patch (US/EU 1.30) and locate what it
    changes in the eboot. If a limit shows up, an `overrides/eboot.json`
    patch is the fix.
  * Record which socket types Ad Hoc Play uses (`net_trace`): datagram
    P2P only, or also `SOCK_STREAM_P2P` (the game imports
    `sceNetListen` / `sceNetAccept` / `sceNetConnect`). Also record
    whether `adhoc_matching` packets carry IP addresses in their payload.
  * **Go / no-go:** playable at 100 ms RTT (with or without a patch), or
    stop here and reconsider Part 2 (`SceLibRudp`) as the WAN route.
  * **0.6.1 test observations (2026-11-27).** Two isolated Steam Deck
    copies created and joined a room and finished *Croaking Fiends in
    the Forest* through a private `tc netem` loopback. Both reached the
    results screen with the same 10:09 clear time. The trials used
    copied saves, invincibility and the damage modifier. Netem applied
    25 ms one-way delay and 1% configured loss, and the measured RTT
    was 50.1 ms. The existing LLE hook raised both peers'
    matching retransmit intervals from 8 to 250 ms.
  * At 100.1 ms measured RTT and 3% configured loss, two copies created
    and joined a room and finished *Croaking Fiends in the Forest* with
    the same 00:34 clear time. In a separate room with the same parameters,
    both copies received the Blank Page pact *Cobblers in Town Center*
    and stayed in combat together. The input driver could not navigate
    to the final target. Both copies also entered *Snakeman at Island*
    and remained connected, but the driver stalled on terrain on the way
    to the Hydra. A third Blank Page run, *Founder in Forest* at 100.1 ms
    and 3% loss, defeated Odin and displayed the same 1:59 clear time
    on both clients.
  * At 200.2 ms measured RTT and 5% configured loss, three guests joined
    the host. One guest returned to the Ad Hoc menu while the host was
    browsing pacts. The guest rejoined and all four fought in the regular
    quest and reached its end transition. The harness expired before a
    results-screen capture. The cause of the guest departure is unverified.
    On a repeat at 200.1 ms and 5% loss, all four entered combat. The host
    and two guests showed the same 00:32 clear time. The fourth guest
    remained in combat after calling `sceNetCtlAdhocDisconnect`, with
    the other players absent. The trigger for the disconnect is unverified.
    A third run at 200.1 ms and 5% loss completed on all four clients after
    one guest rejoined the room. The host and two guests reported 00:46
    and the rejoined guest reported 00:45.
  * The auth, `UDP_NetId` and matching socket creations in this run all
    used type 6 (`SOCK_DGRAM_P2P`). The loopback capture matched the peer
    IPv4 bytes at payload offset 0 in discovery traffic (UDP 36992 to
    36991), and at offsets 4 and 8 in matching traffic (3660 to 3659).
    An overlay therefore needs consistent IPv4 addresses in those paths.
  * Both the regular and Blank Page clears meet the 100 ms playability
    gate with the current LLE hook. These trials did not show a fixed
    latency threshold that would justify an additional eboot override.
* **16a.1 Transport library (`vita3k/net/online/`):**
  * Port/adapt `crypto` (vendored Monocypher: X25519 +
    XChaCha20-Poly1305), `stun`, `upnp`, `discovery` (LAN multicast),
    `dht` (Mainline DHT bootstrap + announce/lookup, namespaced per
    invariant 5) and `overlay` (session-wide virtual IP derivation,
    single-UDP-port framing carrying `(vport, flags, payload)`, hole
    punching, keepalives, relay client mode).
  * Reliable ordered delivery is required if 16a.0 finds
    `SOCK_STREAM_P2P` in Ad Hoc Play, and optional otherwise.
  * Build cleanly under CMake across MSVC/Winsock2 (Windows), POSIX
    (Linux/Steam Deck, macOS) and the Android NDK (`arm64-v8a`). Nativ
    has never been built for Android.
  * Standalone host unit tests: loopback handshake, virtual-IP
    derivation and collision handling, vport mux, simulated packet drop
    and NAT, malformed-packet fuzzing and bounds checks.
* **16a.2 Relay (decide before 16a.1 starts):** players behind
  symmetric NAT or carrier-grade NAT (cellular, many ISPs, the common
  Android case) can't play without one, and the exit criterion requires
  it.
  * Decide between hosting a community relay (cost, uptime, abuse
    handling, rate limits, per-session caps), shipping only a
    self-hostable relay with `[multiplayer] relay = host:port`, or both.
  * Package `nativ-node` or a compatible standalone daemon (GPL, kept
    outside the MIT kit).
  * The DHT's bootstrap nodes are a third-party dependency. List them,
    allow overriding them in config, and fall back to the relay as a
    rendezvous point if the DHT is unreachable.
* **16a.3 Vita3K socket and Ad Hoc NetCtl integration:**
  * In `online` mode, `P2PSocket` (`vita3k/net/src/p2psocket.cpp`):
    * `bind` binds the host socket on `127.0.0.1` (any free port) and
      registers `(vport, loopback port)` with the bridge;
    * `send_packet` to the virtual broadcast goes to the bridge, which
      fans it out to the session's peers; unicast to `198.18.x.y` goes
      to the bridge, which routes it through that peer's tunnel;
    * `recv_packet` translates the bridge's loopback sender back into
      the peer's virtual IP and `vport` in `SceNetSockaddrIn`.
  * `Epoll`, timeouts and `sceNetSocketAbort` need no change (invariant
    2). Test that they behave as in `lan` mode.
  * `SceNetCtl`'s Ad Hoc peer thread
    (`vita3k/modules/SceNetCtl/SceNetCtl.cpp`) takes the node's session
    virtual IP as `netAddr` and the virtual broadcast as `broadcastAddr`
    instead of `net_utils::init_address`'s adapter, so
    `adhoc_matching.suprx` sees plain IPv4 peers without knowing about
    NAT or relays.
  * Verify that `local` and `lan` (including VPN `peers`) are
    unchanged, and that utakata still builds and passes its checks on
    the shared `games` branch.
* **16a.4 Frontend settings, UX, consent and platform permissions:**
  * Extend `[multiplayer]` in `vita3k/games/ss-delta/main.cpp` and the
    shared Multiplayer settings page:
    * `network`: add `online` (opt-in, restart required like the other
      values); the defaults stay `local` on Windows and `lan` elsewhere,
      so a first launch opens no internet sockets;
    * `room_code`: generate (host) or type (guest), keyboard or gamepad
      text entry, live-applied;
    * `relay`: `auto`, `off` or a `host:port` override;
    * `upnp`: off by default (it opens a port on the router), with the
      reason shown in the setting's help;
    * a status line: NAT type, peer count, direct or relayed.
  * Selecting `online` for the first time says what it does: the
    player's IP address is visible to the DHT and to the room's peers,
    and to the relay if one is used.
  * Android (`game-frontend/android/`): confirm `INTERNET`,
    `ACCESS_NETWORK_STATE` and `CHANGE_WIFI_MULTICAST_STATE`, take a
    Wi-Fi multicast lock while `discovery` runs, and handle sockets
    across background/foreground transitions.
  * Update `docs/ONLINE-PLAY.md` (including the privacy note) and the
    release READMEs.
* **16a.5 WAN and cross-platform verification:**
  * Test two to four copies through the overlay:
    1. same-PC multi-instance (`--player 3` / `--player 4`, scratch
       users, over the loopback relay);
    2. two machines on one LAN (multicast + direct punch);
    3. two machines behind separate home NATs (DHT + STUN hole punch);
    4. forced relay with the latency and loss figures 16a.0 passed.
  * Cross-platform: Windows ↔ Steam Deck ↔ macOS ↔ Android (AYN Thor,
    over Wi-Fi and a mobile hotspot), US (`PCSA00152`) ↔ EU
    (`PCSF00532`), a full quest to completion.
* **16a.6 Security review before release:**
  * Fuzz and audit every untrusted-packet parser (`overlay`, `dht`,
    `stun`, `upnp`, `discovery`, relay protocol) for buffer bounds,
    amplification (never send more than received before a handshake)
    and peer-table exhaustion.
  * The bridge forwards only packets from authenticated peers of the
    current room to the guest.

### Part 1 exit criterion

Two players on separate home networks (at least one Windows PC and one
Steam Deck, Mac or Android device), with no VPN installed, set
`network = online` with a shared `room_code`, find each other's room in
**Ad Hoc Play** and play a full quest to completion, both over a direct
hole-punched tunnel and over the relay.

---

## Part 2 — Later transition to full Play Online via NP Matching2 (L–XL)

Start this stage if players need features Ad Hoc Play can't offer:
in-game room passwords and search filters, lobby text chat, kick, host
handover, a working **Play Online** button in Librom, or `SceLibRudp`
for higher-latency and lossier WAN play (for example if 16a.0 finds a
latency limit with no patch).

Part 1's overlay, crypto, DHT, STUN/UPnP, relay, vport mux and virtual
IPs are reused. Room *search* is new: Nativ's Matching2 service runs
locally per host, so finding rooms across the internet needs a
distributed room directory (DHT records or relay-hosted listings) that
Part 1's room codes don't provide.

### What Soul Sacrifice Delta imports for Play Online

From `generated/inventory/eboot/imports.csv`:

* **Core matchmaking and transport:** `SceNpMatching2` (26 imports,
  including `CreateContext`, `ContextStart`, `GetServerLocal`,
  `GetWorldInfoList`, `CreateJoinRoom`, `JoinRoom`, `SearchRoom`,
  `LeaveRoom`, `KickoutRoomMember`, `GrantRoomOwner`,
  `SetRoomDataExternal`, `SetRoomDataInternal`, `GetRoomDataInternal`,
  `SendRoomChatMessage`, plus 4 signaling functions) and `SceLibRudp`
  (19 imports).
* **Auth, identity and dialogs:** `SceNpCommon` (8 `sceNpAuth*` imports,
  including `GetTicket`, `GetEntitlementIdList`, `GetEntitlementById`),
  `SceNpManager` (10 imports, including `sceNpManagerGetAccountRegion`),
  `SceCommonDialog` (`sceNetCheckDialog*`).
* **Potential gates (unverified — hypotheses):**
  * `STN001` online-pass check at `0x812782f4` via
    `sceNpAuthGetEntitlementIdList` ([01-research](01-research.md));
  * `SceNpUtility` (10 imports: `sceNpWordFilter*` for room titles/chat,
    `sceNpLookup*`);
  * `SceNpBasic` (12 imports: friend list, presence, play session log);
  * `SceNpTus` (22 imports) and `SceNpScore` (13 imports), **hypothesis:**
    mostly for Sorcerer Stats / faction war / rankings, possibly queried
    on Play Online entry;
  * `SceNpPartyGameUtil` (8), `SceNpActivity` (3), `SceHttp` (19) /
    `SceSsl` (2).

### Firmware modules to LLE and recompile

| Module (`vs0/sys/external/`) | Size | Notes |
|---|---|---|
| `np_matching2.suprx` | 139 KB | Core Matching2 client; mapped by Nativ from 3.65 (**hypothesis:** 3.74 uses the same wire protocol) |
| `np_common.suprx` | 21 KB | NP common helpers |
| `libssl.suprx` | 238 KB | TLS stack used by `np_matching2` (size comparable to `libSceFt2`, 229 KB) |
| `librudp.suprx` | 57 KB | Reliable UDP stream over UDPP2P |
| `np_signaling.suprx` / `libhttp.suprx` | 33 KB / 79 KB | **Hypothesis:** check in the spike whether `np_matching2` pulls either in on 3.74 |

### Implementation steps (Phase 16b)

* **16b.1 Gatekeeper spike (1–3 sessions, JIT build):**
  * Temporarily disable `cfg.offline`, enable `np_matching2`,
    `np_common`, `libssl`, `librudp` as LLE in `load_module.cpp`, stub
    `sceNetCheckDialog` (Inet/PSN mode → OK) and `psn_signed_in = true`,
    and enter **Librom → Network → Play Online** with
    `SSD_TRACE_IMPORTS=1`.
  * Record the exact call sequence, every missing internal HLE import,
    whether `STN001` entitlement / `SceNpWordFilter` / `SceNpTus` /
    `SceNpScore` / direct `SceHttp` calls block room creation, and
    whether US (`PCSA00152`) and EU (`PCSF00532`) pass the same
    `comm_id`.
  * **Go / no-go checkpoint:** confirm no opaque game-specific server
    protocol (beyond Matching2 + RUDP) blocks Play Online.
* **16b.2 LLE and static recompilation of the online firmware modules:**
  * Implement the internal imports the 4+ modules call. The game itself
    doesn't import these; `np_matching2` and friends do (e.g.
    `SceNetCtl` `sceNetCtlGetNatInfo`, `SceNetInternal`,
    `SceSslInternal`, kernel entropy/cert helpers).
  * Load the new modules in `before_dump_quit`
    (`vita3k/games/ss-delta/main.cpp`), assign non-overlapping fixed
    `load_bases` in [game.json](../game.json) (reserved by `aot_init` /
    `load_self.cpp`), recompile, add any missing ARM/Thumb/NEON forms in
    `third_party/recomp/recomp/`, and pass dynarmic differential tests.
  * Update `third_party/recomp/tools/setup.py` for **incremental module
    builds** (compile only missing modules when upgrading an install,
    instead of recompiling `eboot`), and measure the added build time on
    Windows, Steam Deck, macOS and Android.
* **16b.3 Vita3K NP / HTTP / SSL / NetCtl runtime layer:**
  * Split `cfg.offline` so real Sony hostnames never leave the machine:
    `sceNetResolverStartNtoa` redirects Sony NP/matching domains to
    loopback, while unrecognised external hosts stay blocked.
  * Serve the HTTPS matching-server list locally, and hook `libssl`
    certificate verification (or trust a local CA) so `np_matching2`
    connects to the local service.
  * Implement PSN sign-in ticket construction and the `STN001`
    entitlement response in `SceNpCommon`, `sceNpManagerGetAccountRegion`
    and `SIGNED_IN` callbacks in `SceNpManager`, `sceNetCheckDialog` PSN
    mode in `SceCommonDialog`, `sceNetCtlGetNatInfo` (NAT type 1 +
    virtual IP) in `SceNetCtl`, and `SCE_NET_SO_USECRYPTO` /
    `SCE_NET_SO_USESIGNATURE` / epoll support for `librudp` and
    `np_matching2` over Part 1's bridge.
  * Implement clean pass-through/no-data HLE stubs for `SceNpUtility`
    (`WordFilter` pass-through), `SceNpBasic`, `SceNpTus`, `SceNpScore`,
    `SceNpPartyGameUtil` and `SceNpActivity`, as identified by 16b.1.
* **16b.4 Matching2 server, room directory and room proxy on Part 1's
  overlay:**
  * Port Nativ's `m2_wire`, `m2_server`, `m2_rooms`, `m2_proxy` and
    `basic_msg` into `third_party/vita3k/vita3k/net/online/`, bound to
    Part 1's overlay with the `m2` service tag.
  * Design the distributed room directory for `SearchRoom` and
    `GetWorldInfoList`: what a listing contains, who publishes and
    expires it, and how filters apply, without the O(N²) traffic of a
    public overlay topic.
  * Implement the Matching2 wire opcodes and room-attribute, chat, kick
    and owner-transfer flows Soul Sacrifice Delta uses that Killzone
    didn't (notably `GetWorldInfoList`, `SetRoomDataExternal/Internal`,
    `GetRoomDataInternal`, `SendRoomChatMessage`, `KickoutRoomMember`,
    `GrantRoomOwner`).
  * Handle US ↔ EU `comm_id` mapping if 16b.1 finds they differ.
* **16b.5 Frontend UX, pause and security:**
  * Add `[multiplayer] online_id` (player display name in Play Online,
    max 16 ASCII chars per `SceNpOnlineId`) and show Play Online status
    on the Multiplayer settings page.
  * Extend the cooperative pause (fork `app/src/session_controller.cpp`)
    so opening the settings menu or backgrounding on Android keeps the
    game running during Play Online as it does during Ad Hoc Play.
  * Audit untrusted remote data paths reaching guest memory
    (`np_matching2`, `librudp`, `libssl`, chat strings, room binary
    attributes), and keep forwarding only packets from authenticated
    peers inside the active room/signaling set.
* **16b.6 End-to-end Play Online verification:**
  * Same-PC (`--player 1..4`, scratch users): create public and
    passworded rooms, search with filters, join, send lobby chat, kick a
    member, trigger host handover when the host leaves, play and complete
    a quest.
  * Real WAN/NAT + relay tests across Windows, Steam Deck, macOS and
    Android, US ↔ EU, confirming Ad Hoc Play (`local`, `lan`, `online`)
    still works alongside Play Online.

### Part 2 exit criterion

Two players on separate networks (no VPN, native code without dynarmic)
open **Librom → Network → Play Online**, create a passworded or public
room, find and join it through room search, exchange lobby chat,
complete a quest together and survive a host handover, on Windows,
Linux/Steam Deck, macOS and Android.

---

## Risks and open hypotheses

| # | Risk / hypothesis | Stage | Mitigation |
|---|---|---|---|
| 1 | **Ad Hoc WAN latency limit (hypothesis):** Ad Hoc Play may time out or reject peers above a low RTT (cf. the ~24 ms XLink Kai ping patch on hardware) | 16a.0 | Measure on the existing VPN path before writing overlay code; patch via `overrides/eboot.json` if a limit exists; otherwise reconsider Part 2 (`SceLibRudp`) as the WAN route |
| 2 | **Socket semantics in `online` mode:** epoll, receive timeouts and `sceNetSocketAbort` depend on host fds | 16a.3 | Loopback bridge (invariant 2) keeps real host sockets; test epoll, timeouts and abort as in `lan` mode |
| 3 | **Virtual IP consistency:** guest payloads and the peer thread's self-filter need one address per node, seen the same by all | 16a.1 / 16a.3 | Session-wide addresses derived from public keys with a deterministic collision tie-break (invariant 3) |
| 4 | **Android CGNAT and NDK portability (hypothesis):** Nativ has never been built for Android; carrier-grade NAT often breaks hole punching | 16a.1 / 16a.2 | Relay is a requirement, decided before 16a.1; test on the AYN Thor over Wi-Fi and a mobile hotspot |
| 5 | **Relay hosting and abuse:** bandwidth cost, uptime, DoS exposure | 16a.2 | Decide hosted vs. self-hosted first; rate limits, per-session caps, authenticated handshakes, `[multiplayer] relay` override |
| 6 | **Privacy and router changes:** the DHT and peers see players' IP addresses; UPnP opens router ports | 16a.4 | `online` and `upnp` are opt-in; a first-use notice; the privacy note in ONLINE-PLAY |
| 7 | **Room-code brute force:** DHT infohashes are public | 16a.1 / 16a.4 | Generated high-entropy codes by default, KDF, minimum length for typed codes |
| 8 | **Third-party DHT bootstrap nodes** may be unreachable or blocked | 16a.2 | Configurable bootstrap list; relay as rendezvous fallback |
| 9 | **Game-specific NP gates (hypothesis):** Play Online may require `STN001` entitlement, `SceNpWordFilter`, `SceNpTus` or `SceNpScore` replies | 16b.1 | Resolve in the JIT spike before writing production Part 2 code |
| 10 | **Firmware 3.65 → 3.74 and Matching2 opcode gaps (hypothesis):** Soul Sacrifice uses 26 `SceNpMatching2` calls, beyond Killzone's flow | 16b.1 / 16b.4 | Capture full M2 wire traces in the spike and extend `m2_server`/`m2_rooms` methodically |
| 11 | **Room search across the internet:** Nativ's Matching2 service is local per host | 16b.4 | Design a distributed room directory as a separate step |
| 12 | **Setup build time and upgrades:** ~455 KB of extra firmware modules slows the first build (especially on Android devices) | 16b.2 | Incremental module compilation in `setup.py`; Part 1 adds no modules |
| 13 | **Untrusted packets in guest memory:** remote peers reach recompiled Sony network code (`libssl`/`np_matching2`/`librudp`) | 16a.6 / 16b.5 | Forward only authenticated peers of the current room; fuzz the host-side `online/` parsers |
| 14 | **Shared fork regressions (utakata and existing Ad Hoc):** socket changes live in `third_party/vita3k` `games` | 16a.3 / 16b.3 | `online` behind its own backend switch; `local` and `lan` untouched; utakata's checks in 16a.3 |
