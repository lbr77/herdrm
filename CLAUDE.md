# herdrm — HerdrM

Native macOS console for [herdr](https://herdr.dev) (the terminal workspace manager for
coding agents). Sidebar lists Spaces (herdr workspaces) and Agents; the bottom-left
footer switches devices (Local + remote herdr hosts over SSH); the right pane is a pure
embedded terminal running `herdr agent attach` — no chat composer.

Design canvas (waku-style sidebar, light/dark): `design/` — published as the
"Herdr for Mac" artifact. `design/canvas.json` notes carry the design tokens and specs.

## Layout

- `Packages/HerdrKit` — SPM library (macOS + iOS): NDJSON-over-Unix-socket RPC
  (`SocketRPC`), models, `Device`/`DeviceStore` (persisted to
  `~/Library/Application Support/HerdrM/devices.json`). macOS-only files are
  `#if os(macOS)`-gated: `SSHTunnel` (OpenSSH forward), `HerdrService` facade,
  `ShellEnvironment`, `LocalServer`, `DeviceFileService`, `SSHCredentialStore`.
  `TailcatTokenStore` (Keychain) and `TailcatBridge` (the HerdrKit-side
  coordinator over the embedded bridge) are shared macOS + iOS.
- `Packages/HerdrSSH` — SPM library (iOS 18+): libssh2 + OpenSSL as prebuilt
  arm64 xcframeworks (`Artifacts/PROVENANCE.md`), ported from Heeler's
  HeelerSSH. `SSHConnection` does `direct-streamlocal` to the remote herdr
  socket (one channel per RPC), PTY exec channels for terminal attach.
- `Packages/HerdrTailcat` — SPM library (macOS + iOS): the tailcat
  (WireGuard/DERP) client as a gomobile-built xcframework
  (`Artifacts/Tailcat.xcframework`, rebuilt by `Scripts/build-xcframework.sh`
  from `go/`). `Sources/HerdrTailcat` wraps the generated `Tailcatmobile*`
  symbols in the `TailcatBridge` actor; the shared Go logic lives in
  `go/bridge` and `go/tailcatmobile` (the bindable face).
- `Sources/HerdrM` — macOS SwiftUI app (XcodeGen `project.yml`), Ghostty embed
  via [libghostty-spm](https://github.com/Lakr233/libghostty-spm): the view is
  `AppTerminalView` on a host-managed (inMemory) backend, and
  `Sources/HerdrM/TerminalProcess.swift` owns the local PTY child (forkpty),
  which keeps the light-theme `LightTerminalANSIAdapter` byte rewriting, the
  real exit code, and SIGHUP/SIGKILL reaping in host hands.
- `Sources/HerdrMobile` — iOS/iPadOS SwiftUI app (`HerdrMobile` target, iOS 18,
  iPhone + iPad). Devices are SSH hosts (Ed25519 device key in Keychain or
  password; TOFU host keys); RPC over `HerdrSSH`; terminal = display-first PTY
  attach behind an APC bootstrap marker + native composer (`agent.prompt`) +
  key bar (`pane.send_input` keys). No relay yet — that lands as a second
  `MobileTransport` implementation.
- `design/` — design canvas working files (`*.dc.html` artboards + `canvas.json`).

## Build & test

```sh
make build      # xcodegen + xcodebuild → build/Build/Products/Debug/HerdrM.app
make run
make kit-test   # HerdrKit integration tests (need a running local herdr)
HERDRM_E2E_SSH_TARGET=vincent@10.10.10.87 make kit-test   # + remote SSH E2E
```

xcodebuild needs `-skipPackagePluginValidation` (SwiftTerm ships a build plugin);
the Makefile passes it.

## tailcat devices

A device can connect over [tailcat](https://github.com/tailscale/tailcat) instead
of SSH, via the [`herdr.tailcat` plugin](../herdr_tc) — a `herdr-tailcatd` daemon
on the host that serves two herdr sockets on virtual TCP ports inside a
tailcat WireGuard/DERP tunnel (no listening port, NAT traversal): **6464** is
the API socket, **6465** the client-protocol socket terminal attach speaks.
Add Device →
Tailcat → paste the token (from the host: `herdr plugin action invoke
herdr.tailcat.token`); the token lives in the Keychain
(`TailcatTokenStore`, keyed by device id), never in `devices.json`.

- `Device.Kind.tailcat` carries no payload. Because tailcat exposes **only the
  herdr socket — no shell** — such a device has no file manager, no directory
  picker, no attachments, no OS sniffing, and no standalone shells
  (`Device.hasShell == false`); those paths throw a "no shell over tailcat"
  error and the UI hides their affordances.
- Transport: the tailcat client is embedded in-process as a gomobile
  xcframework (`Packages/HerdrTailcat`), not a spawned helper. One
  `TailcatBridge` per device holds a single tailcat session and re-serves it
  on a per-device local Unix socket (deterministic path under tmpdir), so
  `SocketRPC`, the event stream, and terminal attach all work unchanged —
  attach runs the *local* herdr CLI with `HERDR_SOCKET_PATH` pointed at the
  bridge socket (herdr derives the `-client` socket from it). HerdrKit's
  `TailcatBridgeManager` coordinates: it reads the token from the Keychain and
  hands it straight to the Go runtime (never a process list or env block).
  `Tools/herdr-tailcat-bridge` is a thin standalone CLI over the same shared
  `bridge` Go package, kept for headless use and debugging.
- iOS: the xcframework already builds iOS slices, so RPC and the event stream
  work there in-process. There is no local herdr CLI on iOS to drive
  `HERDR_SOCKET_PATH` attach, though — iOS-over-tailcat terminal stays blocked
  unless the plugin grows a PTY channel. Wiring it into a `MobileTransport`
  remains the open work.

## Release

Repo: github.com/missuo/herdrm. Push a `v*` tag → `.github/workflows/release.yml`
builds Release (Developer ID: MOE AI LLC, hardened runtime), notarizes via
notarytool, staples, Sparkle-signs the zip, generates `appcast.xml`, and
publishes both as a GitHub release. Secrets: MACOS_CERTIFICATE_P12/_PASSWORD,
APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD, SPARKLE_PRIVATE_KEY (EdDSA private
key also lives in the local login Keychain; public key is pinned in project.yml).
Sparkle feed: the release asset `appcast.xml` at `releases/latest/download/`.
Versioning: MARKETING_VERSION from the tag, CFBundleVersion = CI run number.
CHANGELOG.md is mandatory: CI extracts the `## [x.y.z]` section for the GitHub
release notes and the Sparkle update description, and fails if it's missing —
add the section before tagging. The cask in OwO-Network/homebrew-brew is
auto-bumped after each release.

## herdr protocol notes (0.8.0, protocol 19; verified against the live socket)

- Requests are NDJSON `{"id","method","params"}` on `~/.config/herdr/herdr.sock`;
  `params` must be present even when empty (`{}`), or the server rejects the request.
- `tab.create` returns the new pane as `result.root_pane.pane_id`.
- `events.subscribe` takes `{"subscriptions":[{"type":"pane.updated"},…]}`;
  `pane.agent_status_changed` / `pane.scroll_changed` / `pane.output_matched` are
  pane-scoped (require `pane_id`) and cannot be subscribed globally — status changes
  arrive globally as `pane.updated`. Full global kind list: `HerdrEvent.allKinds`.
- Terminal attach: agents use `herdr agent attach <pane_id> --takeover`; bare shells use
  `herdr terminal attach <terminal_id> --takeover` (takes the pane over from other attached
  clients). Remote devices run it through `ssh -tt` with PATH prepended
  (`sshd` exec is not a login shell; herdr lives in `/opt/homebrew/bin` on macOS hosts).
- Agent status buckets sort Blocked > Done > Working > Idle (matches Heeler).

Reference repos: `~/Projects/herdr` (server source), `~/Projects/Heeler` (iOS client,
same domain model), `~/Projects/waku` (sidebar design reference).
