# V1 security boundaries and threat model

## Status and scope

This document describes the implemented security boundary for the local
ReadyPlayerTwo V1 evaluation build. V1 is summon only and screen blind. It is
not approved for external distribution, multi-user use, autonomous check-ins,
screen observation, or persistent conversation memory.

The primary trust goals are:

- Keep the standard OpenAI API key outside the app bundle and app process.
- Start microphone access only after an explicit Summon.
- Keep the credential broker out of the media and conversation-event path.
- Collect no screen content or application content.
- Persist only a narrow, validated interface-preference schema.
- Close the microphone and network session on every handled end or failure
  path.

This is an implementation-backed boundary, not a claim that the host,
operating system, network, third-party binary, or provider cannot be
compromised.

## Trust boundaries

| Component | Trust and responsibility |
| --- | --- |
| Terminal and supervised launcher | Holds the standard key supplied by the developer, creates per-launch values, starts exact child processes, and performs normal cleanup. |
| Loopback credential broker | Holds the standard key while running, authenticates the local app request, allowlists the V1 model and voice, and requests an ephemeral client secret. |
| macOS app | Holds the per-launch bearer and ephemeral client secret, requests microphone permission after Summon, and owns the WebRTC session. It never receives the standard key. |
| WebRTC package and Apple media stack | Capture and play audio, establish the peer connection, and expose transient connection statistics. |
| OpenAI Realtime service | Issues the ephemeral secret and receives the SDP, audio, and Realtime events required for the active conversation. Provider-side handling is externally governed. |
| Local preference store | Persists only validated interface preferences in the app's standard `UserDefaults`. |

The loopback broker is suitable only for a single-user local evaluation. Its
bearer authenticates a launch, not a human identity, device, or distributed
client.

## Exact launch and conversation flow

1. The developer starts `./scripts/run`. The standard key is read from the
   terminal environment if present. Build commands run with that key removed.
2. The launcher applies `umask 077`, creates a private temporary runtime
   directory, generates a 256-bit random per-launch broker bearer, and
   generates a random per-launch OpenAI safety identifier.
3. The launcher starts Node 24 with the standard key, bearer, safety
   identifier, and runtime-config path in the broker process environment.
4. The broker binds exclusively to `127.0.0.1` on an operating-system-selected
   port. It writes a mode `0600` JSON runtime file containing the loopback
   origin, bearer, and schema version.
5. After a loopback health check, the launcher starts exactly one app process.
   It explicitly removes the standard key and passes the loopback origin and
   per-launch bearer to the app environment.
6. Nothing in the voice stack connects or constructs a microphone track at
   app launch. A person must Summon from the character, global shortcut, or
   Status Menu.
7. After Summon, the app enters Connecting and requests macOS microphone
   permission. A denial stops the start flow before WebRTC construction.
8. The app sends the allowlisted model and voice to
   `POST /v1/realtime/client-secret` over loopback HTTP, authenticated by the
   per-launch bearer.
9. The broker hashes and timing-safely compares the bearer, verifies the model
   is exactly `gpt-realtime-2.1`, and verifies the voice is `alloy`, `ash`,
   `ballad`, `coral`, `echo`, `sage`, `shimmer`, `verse`, `marin`, or `cedar`.
   It then sends the standard key only to OpenAI's client-secret endpoint in
   an HTTPS Authorization header.
10. The broker returns only the ephemeral secret value and expiration time,
    with `Cache-Control: no-store`.
11. The app constructs the WebRTC factory, microphone audio track, peer
    connection, and ordered `oai-events` data channel. It creates an audio-only
    SDP offer.
12. The app posts that SDP directly to
    `https://api.openai.com/v1/realtime/calls` with the ephemeral secret. The
    broker does not proxy the SDP, media, or data channel.
13. During the active session, microphone audio and Realtime client events go
    from the app to the OpenAI Realtime service. Remote audio and server events
    return to the app. The broker is no longer in the conversation path.
14. The app sends a screen-blind session configuration with audio output,
    semantic voice activity detection, and an empty tools list. It sends no
    startup response request, so the person speaks first.
15. End, timeout, handled platform suppression, or failure disables the local
    audio track, stops statistics sampling, closes the data channel and peer
    connection, clears transport references, and returns to a non-listening
    state.
16. When the supervised run ends, the launcher stops the exact app and broker
    child processes and normally deletes the runtime file and directory.

The official [Realtime WebRTC
guide](https://developers.openai.com/api/docs/guides/realtime-webrtc)
documents the client-secret, SDP, audio-track, and data-channel protocol used
by steps 9 through 13.

## Data classification and handling

| Data | Classification | Holders and route | V1 persistence |
| --- | --- | --- | --- |
| Standard OpenAI API key | Secret credential | Terminal launcher and broker process, then OpenAI client-secret HTTPS endpoint | ReadyPlayerTwo does not write it. It remains in launcher and broker environment or memory while running. Shell configuration and operating-system artifacts are outside this boundary. |
| Per-launch broker bearer | Secret local credential | Launcher, broker, runtime file, and app environment; sent only over loopback to the broker | Runtime file is mode `0600` in a private temporary directory and is normally deleted on supervised cleanup. It has no independent time limit and is valid while its broker is alive. |
| Ephemeral client secret | Secret provider credential | OpenAI client-secret endpoint, broker response, app memory, and OpenAI SDP Authorization header | The app does not persist it. It is provider-expiring. Swift performs a best-effort clear of one local string after connection, but memory zeroization is not guaranteed. |
| Per-launch safety identifier | Pseudonymous service metadata | Launcher, broker, and OpenAI client-secret request header | Not written by the app. It is random for each launch and is not a stable ReadyPlayerTwo user identifier. Provider handling is external. |
| SDP offer and answer | Sensitive connection metadata | App and OpenAI calls endpoint over HTTPS | Held transiently for negotiation and not intentionally persisted by the app. |
| Microphone and remote audio | Sensitive conversation content | App media stack and OpenAI Realtime WebRTC service; never the broker | No application-owned audio recording or file is created. Provider handling is external. |
| Realtime server and client events | Potentially sensitive session data | App and OpenAI `oai-events` data channel; never the broker | Raw event bytes and decoded lifecycle fields are transient in memory. V1 writes no transcript or conversation history. |
| Input and output energy | Transient derived telemetry | Local WebRTC statistics to runtime waveform | One normalized numeric value is held in the current snapshot. No audio sample or energy history is stored. |
| Interface preferences | Local configuration | App and standard `UserDefaults` | Persists avatar, presence, voice identifier, model identifier, volume, shortcut, and normalized safe parked position until changed or cleared. Validation rejects credential-like identifiers. |
| Screen pixels, window data, application content, clipboard, and input activity | Prohibited V1 data | Not collected or routed | Not persisted because V1 has no collection path. |

V1 has no `memory.md`, conversation memory, transcript store, audio archive,
screen cache, screenshot path, OCR path, or application-content log.

## Microphone timing and indicators

- Permission is checked or requested only from the user-invoked voice
  `start()` path.
- The microphone track is constructed only after permission succeeds and an
  ephemeral secret is obtained.
- Connecting is shown while startup is in progress. The Status Menu reports
  `Microphone: Starting`, `On`, `Muted`, `Closing`, or `Off` from runtime
  state.
- Listening, Thinking, Speaking, Muted, Error, and Ending are visible
  conversation states. The waveform uses current input energy while Listening
  and current output energy while Speaking.
- Mute disables the local WebRTC audio track. End closes the track and
  transport rather than only hiding the interface.
- The first-speech deadline is 60 seconds. After accepted speech, the rolling
  inactivity deadline is 120 seconds and is reset when the runtime enters
  Thinking.
- Sleep, lock, screen saver, Hide during voice, End, Quit, handled transport
  failure, and inactivity timeout stop the active session. Wake and unlock
  never reconnect it.
- AppKit exposes no public Mission Control start or end notification. Active
  Space changes refresh placement, but V1 cannot guarantee Mission Control
  suppression without a separate manual platform validation.

The product indicator communicates application state. It is not a security
boundary and cannot replace the operating system's own microphone controls or
privacy UI, whose behavior is controlled by macOS.

## Screen-blind boundary

V1 may use display geometry, scale factor, pointer-derived display selection,
and public workspace lifecycle notifications to place one Companion and keep
it reachable. A parked position may persist a display identifier plus
normalized coordinates.

V1 does not:

- Capture or sample screen pixels.
- Enumerate application windows or read window titles.
- Inspect the foreground application, document, file, clipboard, or
  notification contents.
- Monitor keyboard or pointer inactivity.
- Use OCR or send visual context to a model.
- Request Screen Recording, Accessibility, Input Monitoring, Camera, Apple
  Events, or file-access permission.
- Give the Realtime session tools or claim that it can see the desktop.

The app sandbox entitlements are limited to the sandbox itself, audio input,
and outbound network access. `./scripts/test` rejects known prohibited V1 APIs,
permission strings, provider-key reads in product source, and credential-like
literals. This source scan is a guardrail, not proof about all behavior inside
the operating system or a third-party binary.

## Retention and persistence boundaries

Application-owned persistence is deliberately narrower than all data the
system touches:

- `UserDefaults` contains only the typed local interface preferences listed
  above.
- The temporary runtime file contains the loopback origin and bearer. Normal
  supervised cleanup deletes it. A hard host failure or unhandled launcher
  termination can leave a mode `0600` artifact requiring local cleanup.
- The standard key, bearer, ephemeral secret, SDP, audio, and events exist in
  process memory or transport buffers while needed. The implementation does
  not guarantee memory zeroization, swap exclusion, or absence from
  operating-system crash diagnostics.
- Application and broker output is redirected away from persistent app logs
  by the supervised launcher. System, network, and provider diagnostics remain
  outside this application-owned boundary.
- Closing a session stops future application capture and transmission. It
  cannot retroactively erase data already received by another component.

Provider-side processing, abuse monitoring, retention, training, residency,
and deletion are governed by current provider policies and the deployment's
agreement. They are not guaranteed by this repository and must be reviewed
against current official terms before any release. This document makes no
zero-retention or provider-deletion claim.

## Threat register

| Threat | Implemented control | Residual risk and required posture |
| --- | --- | --- |
| Standard key reaches the app or bundle | Launcher removes it from app build and launch environments; tests scan app and runtime source; broker alone calls the client-secret endpoint | Launcher and broker memory remain sensitive. A compromised terminal, host, launcher, or broker can steal the key. Never distribute this local broker pattern with a shared key. |
| Unauthorized local client mints secrets | Random 256-bit bearer per launch, private runtime directory, mode `0600` file, loopback bind, exact endpoint, timing-safe bearer comparison | A privileged or compromised same-user process can inspect environments, files, memory, or loopback traffic. The bearer has no human identity and no independent expiry. |
| Broker request redirects off-host | App accepts only `localhost`, `127.0.0.1`, or `::1`; production launcher supplies `127.0.0.1` | Compromise of the host or app environment remains in scope. Loopback HTTP does not protect against a hostile local endpoint with the bearer. |
| App reuses or leaks the ephemeral secret | Secret has a provider expiry, is not persisted, and is used only for SDP authorization | Process-memory compromise or diagnostics can expose copies. Best-effort string clearing is not guaranteed zeroization. |
| Microphone starts without person intent | V1 exposes only explicit Summon inputs; permission and voice start occur in that path; no wake phrase or background listener exists | UI automation, a compromised app, or an unintended shortcut activation can still invoke Summon. Product indicators must remain clear and End immediately available. |
| Microphone remains active after failure | Voice failures close transport; runtime end paths are centralized; mute disables the track; lifecycle and timeout tests cover teardown | Hard crashes and compromised media dependencies are outside app control. Test teardown on every supported target and audio route. |
| Broker receives conversation content | App negotiates SDP and WebRTC directly with OpenAI; broker exposes only health and client-secret endpoints | OpenAI, the WebRTC stack, operating system, and network path still process conversation data or metadata. |
| Sensitive desktop content is captured | No screen APIs or permissions; session instructions declare no screen context; tools are empty; source scans reject prohibited APIs | A person can disclose sensitive information verbally. Dependencies and future changes require review because a source scan is not a complete behavioral proof. |
| Screen text prompt-injects the model | V1 has no screen input, OCR, clipboard input, or application tools | Spoken prompt injection and ordinary model risks remain. Screen prompt injection must be threat-modeled before any V2 observation feature. |
| Conversation content persists locally | No transcript, audio recording, conversation history, or Companion Memory store; server events remain transient | Memory, swap, crash diagnostics, external recording software, and provider systems are outside application-owned persistence. |
| Dependency supply chain is compromised | Exact WebRTC version and revision, Swift package resolution, binary checksum verification, npm lockfile, and install without package scripts | The prebuilt WebRTC binary and upstream release process remain trusted dependencies. Pin or checksum changes require provenance review. |
| Provider retention is assumed from code | Security docs separate application behavior from provider policy | Release owners must verify current provider policy and contract. Do not infer provider deletion or zero retention from session close. |
| Cleanup is skipped | Launcher traps normal exit and signals, stops exact child process IDs, and deletes the runtime artifact | Power loss, hard launcher termination, or operating-system failure can leave the restricted runtime file. Inspect and remove stale artifacts before treating the host as clean. |

## Failure and teardown contract

| Trigger | Required result |
| --- | --- |
| Microphone denial | No WebRTC objects are constructed; Connecting changes to a recoverable error; microphone remains off. |
| Missing broker configuration or secret-fetch failure | No WebRTC transport starts; the runtime exposes an error and requires explicit Retry. |
| OpenAI client-secret authentication failure | The broker discards the upstream body and normalizes an upstream 401 or 403 to status 401 with `upstream_authentication_failed`. |
| OpenAI client-secret rate limit | The broker discards the upstream body and returns status 429 with `upstream_rate_limited`. |
| Other OpenAI response or broker-to-provider network failure | The broker exposes no upstream body or exception text and returns status 502 with `upstream_unavailable`. |
| SDP, data-channel, peer, server, or network failure | Local audio is disabled; statistics stop; channel and peer close; error remains nonspoken and recoverable. |
| End, Hide during voice, platform suppression, or inactivity timeout | Runtime enters Ending, invokes voice stop once for that active generation, and returns to a non-listening state. |
| Sleep, lock, or screen saver | Stage is suppressed and active voice ends. A later platform resume does not restart voice. |
| Mission Control | AppKit provides no public start or end lifecycle event. V1 does not synthesize one or claim automatic suppression; validate visible and input behavior manually on each target macOS release. |
| Broker exits unexpectedly | Launcher stops the exact app child and exits with failure. |
| Terminal interrupt or normal app exit | Launcher stops remaining exact child processes and normally removes its runtime file and directory. |

Teardown is forward-looking: it ends ongoing local capture and transport. It
does not prove deletion of data already processed elsewhere.

## Dependency provenance

- The macOS app targets the selected Apple Xcode SDK and uses AppKit,
  SpriteKit, AVFoundation, and system security controls.
- `stasel/WebRTC` is declared at exact version `150.0.0`. The resolved source
  revision is `6ed87f05368632f71dc95c89c14c051561710925`.
- That release's Swift manifest declares the `WebRTC-M150.xcframework.zip`
  binary checksum
  `f9890492b0016e4c88ab20f07867b8b420054caedc8a692b2ec6ac041f3cf6b2`.
  Swift Package Manager verifies the downloaded artifact against it.
- The broker targets Homebrew Node 24. Its package and lock files currently
  declare no third-party npm packages. The quality gate runs `npm ci` with
  lifecycle scripts disabled before broker tests.
- The OpenAI Realtime endpoints, model, and voice are service dependencies,
  not vendored code. Model or voice allowlist changes require a security and
  behavior review.

Any dependency version, resolved revision, binary URL, checksum, entitlement,
or network endpoint change requires review of this document and the threat
register.

## Verification commands

Run from the repository root:

```bash
./scripts/doctor
./scripts/test
plutil -p App/ReadyPlayerTwo/ReadyPlayerTwo.entitlements
rg -n 'NSMicrophoneUsageDescription' project.yml
rg -n 'exactVersion|f9890492b0016e4c88ab20f07867b8b420054caedc8a692b2ec6ac041f3cf6b2' project.yml
rg -n '6ed87f05368632f71dc95c89c14c051561710925' ReadyPlayerTwo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
rg -n 'OPENAI_API_KEY' App/ReadyPlayerTwo Packages/CompanionRuntime/Sources
rg -n 'CGWindowListCreateImage|ScreenCaptureKit|SCStream|AXUIElement|CGEventTapCreate|NSScreenCaptureUsageDescription' App/ReadyPlayerTwo Packages/CompanionRuntime/Sources project.yml
```

The final two searches must produce no matches. `./scripts/test` is the
authoritative combined gate for privacy scans, Swift formatting, package
tests, broker lockfile installation and tests, app build, and app tests.

## Official protocol references

These verified OpenAI references support the protocol and event-flow
description only. They are not retention guarantees:

- [Realtime API with
  WebRTC](https://developers.openai.com/api/docs/guides/realtime-webrtc)
- [Realtime
  conversations](https://developers.openai.com/api/docs/guides/realtime-conversations)
- [Voice activity detection and semantic
  VAD](https://developers.openai.com/api/docs/guides/realtime-vad#semantic-vad)
