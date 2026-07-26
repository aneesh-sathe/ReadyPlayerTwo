# ReadyPlayerTwo V1 Acceptance Evidence

## Decision

ReadyPlayerTwo V1 is not release-accepted yet.

The deterministic implementation and no-key packaged lifecycle are passing at
implementation commit `40aaf0d`. The remaining gates require a trusted signed
runner, macOS UI-automation authorization, an OpenAI API key, audio hardware and
a human listener, real desktop configurations, and multi-hour observation.
GitHub issues #2 through #11 must remain open until their remaining criteria are
recorded here.

This ledger separates verified evidence from inference. A compiled test, a
scripted Adapter, or a short process soak is never reported as a live voice,
manual visual, accessibility, desktop-integration, or two-hour result.

## Evaluation baseline

| Field | Value |
| --- | --- |
| Evaluation date | 2026-07-26 |
| Implementation commit | `40aaf0d` |
| Hardware family | Apple Silicon |
| macOS | 26.5, build 25F71 |
| Xcode | 26.6, build 17F113 |
| Swift | 6.3.3 |
| Node.js | 24.18.0 |
| Signing available | Ad hoc only |
| OpenAI key available | No |
| UI-automation authorization | No |
| Desktop screenshot authorization | No |

The CoreSimulator version warning printed by Xcode does not affect the macOS
build or test destination.

## Automated quality gate

`./scripts/test` passed twice consecutively after the final behavior change.
Both runs completed the same authoritative checks:

- 5 shell harness suites passed.
- V1 prohibited-capability and credential scans passed.
- Swift formatting passed.
- 36 `CompanionRuntime` tests in 3 suites passed.
- 13 broker tests passed.
- The development-signed macOS app built successfully.
- 102 packaged AppKit tests in 22 suites passed.

Focused suites also passed:

- 18 `CompanionStageTests`, including legal Orion and Athena movement,
  intent-correct quiet holds, 150-millisecond pose crossfades,
  200-millisecond avatar crossfades, display relocation, Reduce Motion, and
  alpha hit testing.
- 9 `AudioRouteMonitorTests`, including complete selected data-source arrays,
  input and output source changes, default-device replacement, partial
  listener cleanup, and stale queued callback rejection.

The ordinary gate deliberately excludes live OpenAI calls and XCUITest
execution.

## Packaged lifecycle evidence

`./scripts/smoke` passed at the evaluation baseline:

- one signed Dockless app launched through the real supervised command;
- the credential broker was healthy and bound only to loopback;
- a duplicate launch was rejected without disturbing the original runtime;
- launch made no microphone access request; and
- terminal interruption left no captured child process alive.

The opt-in `ReadyPlayerTwoPackagedAcceptance` scheme passed
`build-for-testing`. Its XCUITest runner and app-under-test therefore compile
and package. On this Mac, execution stops before any UI test begins with
`LocalAuthentication` code `-2`. This is an authorization blocker, not a passed
or failed product result.

The available XCUITest source covers clean launch, Status Menu presence, Park,
Roam, Hide, Show, Athena selection, no-key Summon error, End, and Quit. It does
not yet constitute evidence for the complete packaged matrix because it has not
executed here and does not cover every parent criterion.

## Resource evidence

A 15-second no-key Roaming run passed through the real supervised launcher at
the evaluation baseline and collected 14 exact-process samples:

| Process | Average CPU | Peak CPU | Start RSS | Peak RSS | End RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Launcher | 0.464% | 0.700% | 2,896 KiB | 2,896 KiB | 2,896 KiB |
| Broker | 0.014% | 0.200% | 86,240 KiB | 86,256 KiB | 86,256 KiB |
| App | 0.021% | 0.300% | 35,280 KiB | 35,280 KiB | 32,752 KiB |

The run enforced the immediate combined 200 MiB resident-memory ceiling and
exact process cleanup. Because it was shorter than 180 seconds, it did not
evaluate settled CPU or continuous RSS growth.

An earlier 180-second implementation checkpoint collected 36 samples and
evaluated one settled CPU and RSS-growth window. Peak CPU was 0.7% for the
launcher, 0.3% for the broker, and 0.1% for the app. Peak RSS was 2,896 KiB,
82,880 KiB, and 35,440 KiB respectively. That result is useful harness evidence
but is not a substitute for the final two-hour Roaming and Park runs.

No two-hour run or operator-verified Park run has been completed. Process
metrics also cannot prove absence of focus theft, invisible input blocking,
unintended speech, unintended microphone access, a lost Companion, or visual
defects. Those remain human observations.

## Visual and accessibility evidence

Verified automated evidence:

- every supplied Orion and Athena frame has stable committed CPU-render hashes
  at 1x and 2x;
- all 128 source frames plus required anchors satisfy alpha, dimensions,
  transparent-background, and transparent-corner contracts;
- six grounded transition pairs keep their anchors within one point;
- legal motion and completed-intent holds are deterministic;
- pose changes use a PRD-compliant 150-millisecond crossfade without repeatedly
  fading an unchanged hold;
- bubble states, waveform behavior, accessible actions, safe placement,
  deterministic sizing, and contrast of at least 7:1 are tested; and
- Reduce Motion preserves static presence and interaction.

This is partial acceptance evidence. Stable hashes are not independently
approved PNG golden images for every legal transition and every bubble state.
Manual VoiceOver, keyboard, light, dark, busy-background, Retina, mixed-scale,
Stage Manager, Spaces, and full-screen review remains pending.

An external `screencapture` attempt during the final live launch failed with
`could not create image from display`. The test harness lacks desktop capture
authorization. This does not add screen capture to the product and does not
count as visual review.

## Voice and privacy evidence

Verified automated evidence:

- only an explicit Summon starts the voice path;
- launch and presence controls do not request microphone access;
- the standard OpenAI key is removed from the app environment and never appears
  in product source, app configuration, persistence, or logs;
- the loopback broker requires a per-launch bearer, allowlists model and voice,
  and returns only short-lived client-secret fields;
- the app exchanges WebRTC media directly with OpenAI rather than proxying it
  through the broker;
- scripted sessions cover person-first semantic VAD, actual input and output
  energy mapping, Mute, End, barge-in cancellation, inactivity timeouts,
  explicit Retry, teardown, and stale callback suppression;
- permission, broker, authentication, rate-limit, transport, peer, and
  audio-route failures map to concise redacted states; and
- privacy scans prohibit screen observation, ambient listening, sensitive
  persistence, and credential-shaped source values.

No live OpenAI speech has been exercised in this environment. Microphone
consent, acoustic echo, audible clipping, a real one-round-trip exchange, ten
turns, 20-turn latency, 20-sample barge-in, live device switching, and
500-millisecond teardown observation remain pending. Follow
[the live voice protocol](live-voice.md) without recording credentials or
conversation content.

## Desktop integration boundary

Deterministic tests cover pointer-display placement, negative coordinates,
display removal, surviving-display preservation, cross-display fades, sleep,
wake, lock policy, and public active-Space refresh behavior.

Real single-display and multi-display arrangements, rotation, scale changes,
Spaces, native full-screen, Stage Manager, screen saver, lock, and sleep still
require packaged manual review. AppKit provides no public Mission Control start
or end event, so Mission Control behavior is manual acceptance only and the app
does not claim automatic lifecycle suppression.

## Issue status

| Issue | Verified implementation evidence | Remaining acceptance gate |
| --- | --- | --- |
| #2 Launch one Dockless Companion | Supervised launcher, singleton smoke, Dockless packaging, diagnostics, no launch microphone request, exact cleanup, runtime tests | Execute packaged UI acceptance and manually verify appearance time and no focus theft |
| #3 Secure summoned voice round trip | Credential isolation, loopback broker, direct WebRTC Adapter, scripted Summon and teardown | One live speech-to-speech round trip and measured microphone teardown |
| #4 Orion Roaming Presence | Asset validation, legal plans, quiet holds, Park, Hide, hit testing, anchors, hashes, crossfades | Real click-through probe, independent transition goldens, and manual pixel review |
| #5 Athena selection | Asset validation, legal airborne motion, state-preserving selection, persistence, hashes, crossfades | Full switch-state packaged matrix, independent goldens, and manual pixel review |
| #6 Control and Summon anywhere | Shared runtime commands, menu, shortcut recording and conflicts, click action, safe preferences | Execute all three packaged Summon entry points from all presence states |
| #7 Desktop resilience | One placement model, topology updates, negative coordinates, relocation fades, sleep and wake policy | Real displays, Spaces, full-screen, Stage Manager, lock, screen saver, and Mission Control review |
| #8 Natural Voice Sessions | Scripted person-first VAD, states, waveform, Mute, timeouts, barge-in, configuration | Live ten-turn listening review, latency samples, barge-in samples, and screen-blind response |
| #9 Safe voice failure recovery | Scripted failures, explicit Retry, route monitoring, teardown, redacted diagnostics | Packaged denial and recovery matrix with live microphone, network, and device changes |
| #10 Accessible visual presentation | Accessibility contracts, keyboard-action wiring, contrast, layout, Reduce Motion, frame hashes | Manual VoiceOver, keyboard, appearance, background, and scale matrix |
| #11 Packaged V1 acceptance | Repeated full gate, real smoke, short and 180-second soak harness evidence, UI test build, setup and privacy docs | UI test execution, one-hour silent work session, final two-hour Roaming and Park soaks, live voice, and full manual matrix |

## Required completion runs

Release acceptance requires all of the following records:

1. Run the `ReadyPlayerTwoPackagedAcceptance` XCUITest scheme on an authorized,
   trusted signed runner and fill any uncovered packaged journeys manually.
2. Complete the live voice protocol with a protected evaluation key, trusted
   microphone consent, headphones, stable broadband, and a human listener.
3. Complete one hour of silent ordinary work and record no focus theft, blocked
   input, speech, microphone access, duplicate runtime, lost Companion, or
   crash.
4. Run `./scripts/soak` for the full two-hour Roaming policy.
5. Run `RPT_SOAK_EXPECTED_PRESENCE=park ./scripts/soak`, manually choose Park
   within the warm-up, and complete the full two-hour Park policy.
6. Complete the manual visual, accessibility, display, Space, full-screen,
   Stage Manager, lifecycle, and click-through matrix on the target hardware.
7. Update this ledger with dates and non-sensitive observations, then close an
   issue only when every acceptance criterion in that issue is satisfied.

