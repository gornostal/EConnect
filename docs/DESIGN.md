# EConnect — Design and Protocol Notes

Native Vala continuity app for elementary OS 8 (Pantheon) that speaks the
KDE Connect protocol so the stock **KDE Connect for Android** and
**KDE Connect for iOS** apps work unchanged.

## Decisions (2026-09-22)

| Topic | Decision |
|---|---|
| Protocol | KDE Connect, protocol version **8** (mandatory since 2025-03; v7 downgrade rejected) |
| Pairing | Standard v8 flow: 8-character verification code compared on both devices, user accepts |
| Trust / session | Pairing certificate is **persisted** on disk; the app only **listens and connects while its window is open**. No background daemon, no autostart in v1 |
| App shape | Single windowed GTK4 + Granite 7 app |
| v1 features | Text clipboard sync (both directions), file/URL/text share (both directions), send screenshot to phone, receive images into a folder |
| Home screen | Preview of the last 5 photos and screenshots per device. Android: pulled via SFTP plugin from `DCIM/Camera` and `Pictures/Screenshots`. iPhone: last 5 images the phone shared to the desktop (no SFTP on iOS) |
| Out of scope v1 | Notifications, battery, MPRIS, SMS, telephony, run commands, remote input, Wingpanel indicator |

## Toolchain on this machine

* elementary OS 8 (circe), Vala 0.56.17, Meson, Ninja present.
* Need: `sudo apt install libgtk-4-dev libgranite-7-dev libgnutls28-dev libssh-dev libjson-glib-dev`
* TLS via GIO `GTlsConnection` (glib-networking GnuTLS backend); JSON via json-glib; SFTP via libssh (vapi to be written or vendored).
* Certificate generation currently shells out to the `openssl` CLI (RSA 2048, 10 years, CN = deviceId). Switch to GnuTLS once `libgnutls28-dev` is in the build so notBefore can be back-dated.
* Build core + CLI only: `meson setup build -Dgui=false && ninja -C build`, then `build/src/econnect-cli -v` (`help` lists commands).

## Protocol reference (verified against kdeconnect-kde master, 2026-09)

### Packet
Newline-delimited JSON on one TLS socket.
```json
{"id": 1695400000000, "type": "kdeconnect.ping", "body": {},
 "payloadSize": 1234, "payloadTransferInfo": {"port": 1739}}
```
* `id` — epoch ms, informational.
* `type` — matches `^kdeconnect(\.[a-z_]+)+$`.
* `payloadSize` / `payloadTransferInfo` — optional, only for packets carrying a file.

### Identity — `kdeconnect.identity`
`deviceId` (32–38 alphanumeric chars, stable, generated once), `deviceName`
(1–32 chars, no `"',;:.!?()[]<>`), `deviceType` (`desktop|laptop|phone|tablet|tv`),
`protocolVersion` (8), `incomingCapabilities`, `outgoingCapabilities`
(arrays of packet types), `tcpPort` (LAN only). Max packet size 8192 bytes.

### Discovery and connection (LAN backend)
1. Every device listens on **UDP 1716** and binds a TCP listener on the first free port in **1716–1764**.
2. A device broadcasts a *discovery* identity (`deviceId`, `deviceName`, `protocolVersion`, `tcpPort`) over UDP on start, on refresh and when it needs peers.
3. The **receiver of the broadcast (A) opens a TCP connection** to the advertised `tcpPort` and writes one plaintext line: a *connection* identity packet with `deviceId`, `deviceName`, `protocolVersion`, **`targetDeviceId`** (the peer's id) and **`targetProtocolVersion`**. The accepting side (B) rejects it if `targetDeviceId` is not its own id or the protocol version is not 8.
4. **TLS roles are the reverse of the TCP roles:** A (TCP client) becomes the **TLS server**, B (TCP server) becomes the **TLS client**. Both present long-lived self-signed certificates (CN = deviceId); the server requires a client certificate.
5. **v8:** immediately after the handshake *both* sides write their **full identity** (with `deviceType`, `incomingCapabilities`, `outgoingCapabilities`) over TLS, then each reads the other's. `deviceId` and `protocolVersion` must equal the plaintext ones, else the connection is dropped (Nov 2025 auth-bypass advisory). Reference implementation waits 1 s for it.
6. If the peer is already paired, the presented certificate must be identical to the pinned one. Unpaired peers may present any self-signed cert. A new link to a known device replaces the old one.

### Pairing — `kdeconnect.pair`
* Body: `pair: true|false`, `timestamp: <seconds since epoch>` (required on request in v8).
* States: NotPaired → Requested / RequestedByPeer → Paired. Request times out after **30 s**. Reject if `|remote_ts − local_ts| > 1800 s` ("clocks out of sync").
* Verification key: `a = local_pubkey_DER`, `b = peer_pubkey_DER`; if `a < b` swap so the larger is first; `SHA256(a ‖ b ‖ decimal(timestamp))`; show **first 8 hex chars, uppercase**.
* Unpair: send `pair: false`, forget the certificate.

### Payload transfer (files)
Sender opens a TLS server socket on a port in **1739–1764**, puts it in
`payloadTransferInfo.port`, sends the packet, streams `payloadSize` bytes.
Receiver connects with the same certificates and reads until size reached.

### Plugins used in v1
* **Clipboard** — `kdeconnect.clipboard` `{content, timestamp}`; `kdeconnect.clipboard.connect` sent on link-up with current content. Text only.
* **Share** — `kdeconnect.share.request` with either `text`, `url`, or a file payload plus `filename`, `creationTime`, `lastModified`, `numberOfFiles`, `totalPayloadSize`, `open`.
* **SFTP (Android only)** — desktop sends `kdeconnect.sftp.request {startBrowsing: true}`; phone replies `kdeconnect.sftp {ip, port, user, password, multiPaths[], pathNames[]}`. Connect with libssh, list newest files in camera/screenshot dirs, download thumbnails.
* **Ping** — `kdeconnect.ping` for connectivity checks in the UI.

### Mobile client capabilities
| Plugin | Android | iOS |
|---|---|---|
| Clipboard | yes, background | only while app is foreground |
| Share | yes | yes, via share sheet |
| SFTP | yes | **no** |
| Notifications, SMS, telephony, MPRIS | yes | no |
| Ping, Battery, FindMyPhone, Presenter, RemoteInput, RunCommand | yes | yes |

## Status

* Core (identity, discovery, TLS link, v8 handshake, pairing, ping, share, history) builds and is verified between two local instances via `econnect-cli`: discovery both ways, matching verification codes (cross-checked against openssl), pinned reconnect, text/URL/file share.
* A real Android phone (KDE Connect app) on the LAN discovered the GUI build, completed the v8 handshake and sent a pair request; the pairing dialog appeared with a code. Full pairing and file exchange with the phone still to be confirmed by hand.
* GUI (GTK4 + Granite 7): device sidebar, device page with Pair/Unpair, Send Files, Send Screenshot (xdg portal), text/link entry, recent images strip, received-items list, toasts, desktop notifications. Clipboard plugin (text) included.
* Not done yet: SFTP gallery pull for Android, settings (device name, download folder), app icon, translations, GnuTLS-native certificate generation.

Run: `meson setup build && ninja -C build && build/src/io.github.agornostal.econnect` (or `sudo ninja -C build install`).

## Module layout
```
src/
  Application.vala          Granite.Application, single window
  Core/Identity.vala        deviceId + certificate generation/storage
  Core/Discovery.vala       UDP 1716 broadcast/listen
  Core/LanLink.vala         TCP + GTlsConnection, v8 identity re-check, NDJSON framing
  Core/Pairing.vala         state machine, verification key, timestamp checks
  Core/Device.vala          per-device state, capabilities, plugin dispatch
  Core/Packet.vala          json-glib (de)serialisation
  Plugins/Clipboard.vala
  Plugins/Share.vala        incl. payload server/client
  Plugins/Sftp.vala         libssh gallery pull (Android)
  UI/MainWindow.vala        device list + home previews
  UI/PairDialog.vala        code comparison
  UI/DevicePage.vala        send text / file / screenshot, recent images
data/  desktop file, appdata, gschema, icons
```

## Sources
* https://valent.andyholmes.ca/documentation/protocol.html
* https://github.com/KDE/kdeconnect-meta/blob/work/protocol-schemas/protocol.md
* https://github.com/KDE/kdeconnect-kde (core/backends/lan, core/backends/pairinghandler.cpp)
* https://kde.org/info/security/advisory-20250418-3.txt (v8 time-based verification code)
* https://kde.org/info/security/advisory-20251128-1.txt (v8 identity mismatch bypass)
* https://github.com/KDE/kdeconnect-ios (plugin list)
