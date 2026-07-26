# ReadyPlayerTwo V1 Tracer-Bullet Issues

These ten issues divide V1 into narrow, complete, dependency-ordered slices. Each slice is independently demoable or verifiable and crosses the relevant runtime, platform, presentation, integration, and test boundaries.

GitHub publication is pending integration issue-write permission. Replace each parent placeholder and slice dependency with the real GitHub issue reference when publishing in dependency order.

## Dependency graph

1. Launch one Dockless Companion
2. Prove a secure summoned voice round trip
   - Blocked by Slice 1
3. Give Orion polished Roaming Presence
   - Blocked by Slice 1
4. Add Athena with state-preserving selection
   - Blocked by Slices 2 and 3
5. Control and Summon the Companion from anywhere
   - Blocked by Slices 2 and 3
6. Keep one Companion reachable across desktop changes
   - Blocked by Slices 2 and 3
7. Make Voice Sessions natural and interruptible
   - Blocked by Slices 2 and 3
8. Recover safely from Voice Session failures
   - Blocked by Slice 7
9. Make desktop companionship accessible and visually dependable
   - Blocked by Slices 4, 5, and 7
10. Pass packaged V1 acceptance
    - Blocked by Slices 6, 8, and 9

Slices 2 and 3 can proceed in parallel after Slice 1. Slices 4, 5, 6, and 7 become independently grabbable once their blockers are complete.

## Slice 1: Launch one Dockless Companion

### Parent

`<PRD issue>`

### User stories covered

US-001 through US-006 and US-044 through US-045.

### What to build

Deliver the smallest complete local macOS Companion path. One terminal command must build and launch a development-signed Dockless app, start and supervise a loopback broker process, display exactly one transparent Orion presence, and expose a persistent Status Menu.

Establish `CompanionRuntime` as the single high behavioral Seam. Launch, diagnostics, and Quit must pass through its public command and snapshot Interface so subsequent motion, voice, and platform behavior can be added without moving product state into AppKit or the Status Menu.

The first slice may use a neutral static Orion pose and an unavailable voice state. It must still behave as a real local app: no Dock icon, no main window, no focus theft, no protected permission request, no duplicate runtime after a second launch, and no orphaned process after Quit or terminal interruption.

### Acceptance criteria

- [ ] One documented terminal command builds the local app bundle, starts the loopback broker, launches the bundle, and supervises both processes.
- [ ] The app uses a stable bundle identifier and local development signature.
- [ ] Exactly one Status Menu item and one transparent Orion presence appear within two seconds on the target Mac.
- [ ] The app has no Dock icon and no conventional main window.
- [ ] The Orion panel does not activate the app or take keyboard focus from the foreground application.
- [ ] Launch does not request microphone, Screen Recording, Accessibility, Input Monitoring, Camera, or file access.
- [ ] A second launch activates or reports the existing instance without creating another Companion, Status Menu, runtime, broker, or audio engine.
- [ ] Diagnostics distinguish app-running, broker-healthy, and voice-not-configured states without exposing secrets.
- [ ] Status Menu Quit and terminal interruption close the panel, Status Menu, app, and broker without leaving a process behind.
- [ ] A behavior test first fails and then passes through the public `CompanionRuntime` Interface.
- [ ] A packaged-app end-to-end test verifies launch, single-instance behavior, absence of a Dock icon, and clean Quit.

### Blocked by

None - can start immediately.

## Slice 2: Prove a secure summoned voice round trip

### Parent

`<PRD issue>`

### User stories covered

US-027 through US-032 and US-036 through US-041.

### What to build

Deliver the first real, explicitly summoned Voice Session through the complete security boundary.

A Status Menu Summon must request microphone permission, obtain a short-lived Realtime client secret from the loopback broker, connect directly to OpenAI over WebRTC, let the person speak first, play one spoken Companion response, and end cleanly. A small visible conversation state and audio-driven waveform are sufficient for this proof.

The standard OpenAI API key must remain only in the broker. The launcher must remove it from the app environment, and the broker must bind only to loopback, require a random per-launch bearer, allowlist session configuration, and never proxy audio.

Implement the Realtime and broker boundaries behind replaceable production and scripted test Adapters. This slice is the early feasibility gate for capture, playback, echo behavior, and teardown.

### Acceptance criteria

- [ ] Summon is the only action that requests microphone access or begins a connection.
- [ ] With valid configuration, a person can Summon, speak first, hear one OpenAI Realtime response, and End the Voice Session.
- [ ] A visible Connecting, Listening, Speaking, and End experience makes the microphone and connection state unambiguous.
- [ ] The waveform follows real input and output energy and stops when the corresponding audio stops.
- [ ] The standard API key is absent from the app bundle, app process environment, app memory configuration, persistence, and logs.
- [ ] The broker binds only to loopback, authenticates with a random per-launch bearer, allowlists model and voice configuration, and returns only a short-lived client secret.
- [ ] Audio travels directly between the app and OpenAI rather than through the broker.
- [ ] Missing configuration leaves visual presence usable and reports Voice Not Configured without requesting microphone permission.
- [ ] End closes capture, playback, peer connection, and short-lived credentials, with observable microphone closure within 500 milliseconds.
- [ ] Audio, transcripts, conversation content, standard credentials, and client secrets are never persisted or logged.
- [ ] The WebRTC dependency is pinned and provenance-verified behind a replaceable Adapter.
- [ ] A scripted Adapter test exercises the complete public `CompanionRuntime` path without a live account.
- [ ] An opt-in live smoke test proves one actual speech-to-speech round trip on the target Mac.

### Blocked by

- Slice 1: Launch one Dockless Companion

## Slice 3: Give Orion polished Roaming Presence

### Parent

`<PRD issue>`

### User stories covered

US-009 through US-012, US-016, US-019 through US-023, and US-026.

### What to build

Turn the initial Orion presence into a polished, manifest-driven Companion on one display.

The person must be able to observe silent Roaming Presence, Park Orion through the Status Menu or by dragging, Hide and Show it, and continue working through transparent panel regions without blocked clicks. Motion must use only Orion's supported walk, climb, cling, jump, and landing states. Unsupported exits must complete behind display edges.

The runtime must validate assets before presentation, plan deterministic legal transitions, align rendering to device pixels, preserve anchors, and bridge unavoidable discontinuities with short crossfades. Tests must observe behavior through `CompanionRuntime`, while deterministic clock and randomness Adapters make paths reproducible.

### Acceptance criteria

- [ ] Every Orion manifest, frame, dimension, anchor, frame rate, and referenced transition validates before the Companion appears.
- [ ] Roaming Presence consists of deliberate legal movement bursts separated by quiet holds and never initiates speech.
- [ ] Orion walks in both directions and can climb, cling, jump, and land using only supported states.
- [ ] Orion never visibly climbs down, invents a ledge exit, moonwalks, or reverses pose for one frame.
- [ ] Unsupported climb exits finish behind a display edge.
- [ ] Park stops autonomous movement at a reachable position, and dragging Orion enters Park.
- [ ] Hide removes Orion from the Desktop Stage while the Status Menu remains available, and Show restores it safely.
- [ ] Ending a Voice Session restores the prior Roaming, Parked, or Hidden state.
- [ ] Rendered frames remain device-pixel aligned with grounded foot-anchor drift of at most one point.
- [ ] Per-frame alpha hit testing, with no more than eight points of padding, allows text selection, scrolling, dragging, resizing, and file drops through transparent pixels.
- [ ] Golden renders cover every Orion state and legal transition at 1x and 2x scale.
- [ ] Deterministic public-interface tests cover Roam, Park, drag-to-Park, Hide, Show, and voice-state restoration.
- [ ] Manual pixel review finds no frame flash, crop jump, opaque rectangle, alpha halo, or unsupported transition.

### Blocked by

- Slice 1: Launch one Dockless Companion

## Slice 4: Add Athena with state-preserving selection

### Parent

`<PRD issue>`

### User stories covered

US-019, US-024, and US-026.

### What to build

Add Athena as a complete alternative Companion using only the existing Athena manifest and sprites.

Athena must walk, take off, glide vertically, hover, drift slowly while airborne, and land without inventing fast horizontal flight. The person must be able to switch between Orion and Athena from the Status Menu while Roaming, Parked, Hidden, or in a Voice Session. Selection must preserve product state, ground the incoming character through a short fade, and persist across safe relaunches.

### Acceptance criteria

- [ ] Every Athena frame, anchor, frame rate, and transition validates before Athena is selectable.
- [ ] Athena walks in both directions, takes off, glides vertically, hovers, drifts slowly, and lands using only supported states.
- [ ] Athena never uses or visually implies unsupported fast horizontal flight.
- [ ] The Status Menu identifies the selected Companion and switches between Orion and Athena.
- [ ] Switching preserves Roaming, Parked, or Hidden presence state.
- [ ] Switching during a Voice Session preserves that single session without opening another connection or microphone capture.
- [ ] The incoming Companion appears through a brief grounded transition without a crop jump, anchor jump, or unsupported intermediate pose.
- [ ] The selected Companion persists across normal Quit and relaunch without persisting conversation content.
- [ ] Golden renders cover every Athena state and legal transition at 1x and 2x scale.
- [ ] Public-interface tests cover switches while grounded, climbing, hovering, Parked, Hidden, and conversational.
- [ ] Manual pixel review finds no moonwalk, frame flash, opaque rectangle, alpha halo, or unsupported transition.

### Blocked by

- Slice 2: Prove a secure summoned voice round trip
- Slice 3: Give Orion polished Roaming Presence

## Slice 5: Control and Summon the Companion from anywhere

### Parent

`<PRD issue>`

### User stories covered

US-005 through US-012 and US-027.

### What to build

Complete the person-controlled entry points and Status Menu.

The person must be able to Summon by clicking the visible Companion, using a configurable global shortcut, or choosing the Status Menu command. Roam, Park, Hide or Show, Companion selection, shortcut settings, voice settings, diagnostics, and Quit must remain available from the Status Menu. These inputs must translate into the same `CompanionRuntime` commands and own no competing product state.

Summon must work from Roaming, Parked, and Hidden states. A second Summon during an active Voice Session must reveal the current session without creating another session. Safe non-sensitive interface preferences must persist locally.

### Acceptance criteria

- [ ] Clicking a visible Companion Summons it without stealing keyboard focus before the click.
- [ ] Control + Shift + Space Summons by default without Accessibility or Input Monitoring permission.
- [ ] The person can configure the shortcut, and a conflict is reported without silently replacing another binding.
- [ ] Status Menu Summon changes to End Conversation while a Voice Session is active.
- [ ] Summon works from Roaming, Parked, and Hidden states.
- [ ] Summon from Hidden reveals the Companion for the Voice Session, and End restores Hidden.
- [ ] A second Summon reveals the existing Voice Session and never creates duplicate capture, playback, peer connection, or state.
- [ ] Roam, Park, Hide or Show, Companion, shortcut, voice, diagnostics, and Quit commands remain available as appropriate.
- [ ] Menu checkmarks, labels, microphone state, and connection state reflect the latest runtime snapshot rather than locally duplicated state.
- [ ] Safe interface preferences persist, while credentials and conversation content do not.
- [ ] Character click, shortcut, and Status Menu behavior are covered through the same public runtime Interface.
- [ ] Packaged-app tests verify Summon and End through all three entry points and from all three presence states.

### Blocked by

- Slice 2: Prove a secure summoned voice round trip
- Slice 3: Give Orion polished Roaming Presence

## Slice 6: Keep one Companion reachable across desktop changes

### Parent

`<PRD issue>`

### User stories covered

US-013 through US-018 and US-037.

### What to build

Make the Desktop Stage reliable across the person's real macOS environment while preserving exactly one Companion.

Fresh launch and Summon must select the display containing the pointer. Autonomous movement remains on one display, while Move to Current Display and cross-display Summon relocate through a short edge fade. Display topology, Spaces, native full-screen, Mission Control, screen saver, lock, sleep, and wake must never duplicate or strand the Companion.

Platform lifecycle events must enter through the same runtime Interface. Sleep and lock must end any Voice Session and close the microphone. Wake must restore safe visual presence but never reconnect or listen automatically.

### Acceptance criteria

- [ ] Exactly one Companion remains present across single-display and multi-display arrangements, including negative coordinates.
- [ ] Fresh launch and Summon choose the display containing the pointer.
- [ ] Autonomous Roaming Presence remains on its current display.
- [ ] Move to Current Display and a Summon from another display relocate the Companion through a short edge fade.
- [ ] Display addition, removal, rotation, resolution, scaling, and arrangement changes recompute bounds and keep the Companion reachable.
- [ ] The Companion preserves a consistent point size on Retina, non-Retina, and mixed-scale displays.
- [ ] Roaming and Park follow the active regular Space without duplication.
- [ ] Ordinary presence hides in another app's native full-screen Space, while explicit Summon may reveal it for the Voice Session.
- [ ] Mission Control, screen saver, and screen lock hide or pause the Desktop Stage without leaving an interactive invisible panel.
- [ ] Sleep and lock end active Voice Sessions and close the microphone within 500 milliseconds.
- [ ] Wake and unlock never reconnect, reopen the microphone, or resume a failed Voice Session without a new Summon.
- [ ] Deterministic platform tests cover display topology changes, Spaces, full-screen, lock, sleep, wake, and display removal.
- [ ] Packaged-app testing confirms the Companion never duplicates, becomes irretrievable, or blocks desktop input during these transitions.

### Blocked by

- Slice 2: Prove a secure summoned voice round trip
- Slice 3: Give Orion polished Roaming Presence

## Slice 7: Make Voice Sessions natural and interruptible

### Parent

`<PRD issue>`

### User stories covered

US-027 through US-035 and US-042.

### What to build

Complete the intended summoned conversation experience.

Summon must immediately stop autonomous travel, settle the Companion into an attentive pose, and present a bubble that truthfully communicates Connecting, Listening, Thinking, Speaking, Muted, Error, and Ending. The person always speaks first. Semantic VAD must tolerate natural pauses, while barge-in must cancel active playback and stale buffered audio promptly.

The waveform must reflect actual input or output energy. Mute, End, first-speech timeout, ongoing inactivity timeout, model and voice configuration, and restoration of the previous presence state must work through the same runtime Interface. The Companion must describe itself honestly as screen-blind when asked about visible content.

### Acceptance criteria

- [ ] Summon stops autonomous travel and settles the Companion into an attentive stable pose within 350 milliseconds.
- [ ] The person always speaks first, and the Companion never greets or starts speaking merely because a connection opened.
- [ ] The bubble truthfully exposes Connecting, Listening, Thinking, Speaking, Muted, Error, and Ending.
- [ ] The waveform follows actual input energy while Listening and output energy while Speaking, then returns to rest.
- [ ] Semantic VAD begins at low eagerness and does not routinely commit natural pauses prematurely.
- [ ] Barge-in cancels model output, local playback, and stale buffered audio without replaying an old segment.
- [ ] Audible Companion speech stops within 250 milliseconds at p95 during controlled barge-in testing.
- [ ] Mute closes or suppresses microphone input unambiguously and unmute requires an explicit person action.
- [ ] No first speech for 60 seconds ends the Voice Session.
- [ ] Two minutes without speech after conversation begins ends the Voice Session.
- [ ] End restores the exact prior Roaming, Parked, or Hidden state.
- [ ] Model and voice are configuration rather than embedded constants.
- [ ] Asking about visible desktop content produces an honest screen-blind response.
- [ ] A scripted Adapter covers every state and transition through `CompanionRuntime`.
- [ ] An opt-in live ten-turn conversation supports natural pauses and interruption without clipped, repeated, overlapping, or stale audio.

### Blocked by

- Slice 2: Prove a secure summoned voice round trip
- Slice 3: Give Orion polished Roaming Presence

## Slice 8: Recover safely from Voice Session failures

### Parent

`<PRD issue>`

### User stories covered

US-031 through US-042.

### What to build

Make every Voice Session failure private, recoverable, and incapable of turning into ambient listening.

Permission denial, missing configuration, broker failure, authentication failure, network loss, rate limiting, peer loss, and audio-device removal must leave visual presence usable and show a concise nonspoken recovery state. Failed sessions must release the microphone and require explicit Retry. They must never reconnect or resume listening silently.

Complete privacy-redacted diagnostics and input or output device behavior while preserving the standard credential and data boundaries.

### Acceptance criteria

- [ ] Microphone denial leaves Roaming Presence and Status Menu controls usable and explains how the person can recover.
- [ ] Missing configuration, broker failure, authentication failure, network loss, rate limiting, peer loss, and audio-route failure each produce an accurate nonspoken error state.
- [ ] Failures while Connecting, Listening, Thinking, and Speaking close capture and playback safely.
- [ ] Every unrecoverable failure closes the microphone within 500 milliseconds.
- [ ] Retry is explicit, starts one new connection, and never creates duplicate capture, playback, or peer state.
- [ ] A failed session never reconnects, listens, or speaks automatically after network recovery, wake, unlock, or device return.
- [ ] Removal or change of the selected input or output device ends or updates the Voice Session without an echo loop or stale route.
- [ ] Visual motion, Park, Hide, Show, Companion selection, diagnostics, and Quit remain usable after every voice failure.
- [ ] Structured diagnostics contain only redacted lifecycle, failure category, and performance data.
- [ ] Audio, transcripts, conversation content, API keys, client secrets, and per-launch bearer values never appear in logs or persistence.
- [ ] Asking diagnostics about provider data behavior states the documented Realtime retention boundary accurately.
- [ ] Scripted failure tests inject each failure through public ports and assert only observable runtime, menu, bubble, and microphone behavior.
- [ ] A packaged-app matrix verifies denial, disconnect, route removal, Retry, and Quit without an app restart.

### Blocked by

- Slice 7: Make Voice Sessions natural and interruptible

## Slice 9: Make desktop companionship accessible and visually dependable

### Parent

`<PRD issue>`

### User stories covered

US-016, US-021 through US-025, US-029, and US-043 through US-044.

### What to build

Complete the accessibility and visual-quality path for both Companions and the full conversation experience.

Reduce Motion must replace autonomous traversal with a calm static presence and simple fades. Status Menu controls, settings, bubble actions, connection state, microphone state, and errors must be understandable through VoiceOver and keyboard operation. Character and bubble presentation must remain legible and reachable across appearance, scale, and busy desktop backgrounds without compromising click-through behavior.

### Acceptance criteria

- [ ] Reduce Motion disables autonomous traversal while preserving static presence, Summon, Park, Hide, Show, and simple fades.
- [ ] VoiceOver exposes meaningful labels, values, and actions for Status Menu items, settings, bubble controls, microphone state, connection state, and recoverable errors.
- [ ] Every actionable control is operable by keyboard without stealing focus during ordinary Roaming Presence.
- [ ] Light and dark appearances preserve readable bubble text, controls, waveform, focus indicators, and status icon.
- [ ] Bubble placement remains within safe display bounds and avoids the Companion's face, menu bar, and Dock.
- [ ] Character and bubble remain visually stable on 1x, 2x, and mixed-scale displays.
- [ ] Busy-background review finds no unreadable state, opaque panel rectangle, crop defect, or alpha halo.
- [ ] Transparent areas remain click-through after accessibility and visual treatments are enabled.
- [ ] Golden renders cover both Companions, every conversation state, light and dark appearance, and 1x and 2x scale.
- [ ] Manual VoiceOver, keyboard, Reduce Motion, light, dark, busy-background, and scaled-display review passes on the target Mac.

### Blocked by

- Slice 4: Add Athena with state-preserving selection
- Slice 5: Control and Summon the Companion from anywhere
- Slice 7: Make Voice Sessions natural and interruptible

## Slice 10: Pass packaged V1 acceptance

### Parent

`<PRD issue>`

### User stories covered

US-001 through US-045.

### What to build

Harden and verify the complete locally run V1 as a packaged product rather than a collection of Modules.

Run the highest-value journeys through the real app shell and `CompanionRuntime`, using deterministic Adapters for ordinary automation and an opt-in live OpenAI path for listening and latency validation. Fix every discovered functional, visual, accessibility, privacy, performance, lifecycle, formatting, lint, or flaky-test defect before declaring V1 complete.

Finish concise developer setup, privacy behavior, diagnostics, and troubleshooting documentation.

### Acceptance criteria

- [ ] One documented terminal command consistently produces one app, one Status Menu, one Companion, and one supervised broker.
- [ ] The Companion appears within two seconds on the target Mac and Quit leaves no process, panel, audio engine, or menu item.
- [ ] Packaged tests cover clean launch, second launch, all Summon entry points, Roam, Park, drag-to-Park, Hide, Show, Companion switch, permission denial, network loss, Retry, display changes, Spaces, full-screen, lock, sleep, wake, and Quit.
- [ ] A one-hour silent Work Session produces no speech, microphone access, focus theft, blocked clicks, duplicate runtime, lost Companion, or crash.
- [ ] Across 20 controlled live turns on stable broadband, response audio starts within 1.5 seconds median and 2.5 seconds at p95 after end of speech.
- [ ] Controlled barge-in stops audible Companion speech within 250 milliseconds at p95.
- [ ] A two-hour soak shows idle or Park CPU below 2 percent, ordinary roaming CPU below 5 percent, resident memory below 200 MB, and no continuous memory growth.
- [ ] The soak produces no duplicate runtime, irretrievable Companion, invisible input blocker, orphaned microphone, broker leak, or crash.
- [ ] Repository inspection and runtime tests confirm that screen capture APIs and prohibited permission requests are absent.
- [ ] Repository inspection and runtime tests confirm that audio, transcripts, conversation content, standard credentials, and client secrets are neither persisted nor logged.
- [ ] All automated tests, golden renders, formatting, and lint checks pass repeatedly without flakiness.
- [ ] Manual pixel review passes for both Companions across light, dark, busy-background, Retina, scaled-display, Spaces, full-screen, Stage Manager, and Reduce Motion scenarios.
- [ ] Manual VoiceOver and keyboard review passes.
- [ ] Developer documentation explains setup, configuration, launch, privacy boundaries, diagnostics, live smoke testing, troubleshooting, and clean shutdown.
- [ ] Every V1 Definition of Done item in the parent PRD is either verified or explicitly linked to reproducible evidence.

### Blocked by

- Slice 6: Keep one Companion reachable across desktop changes
- Slice 8: Recover safely from Voice Session failures
- Slice 9: Make desktop companionship accessible and visually dependable
