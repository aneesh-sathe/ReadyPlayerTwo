# ReadyPlayerTwo V1 Scope Plan

## Outcome

V1 is a locally run, macOS-only Companion prototype with two proof points:

1. Orion and Athena feel polished, fluid, and naturally present across the desktop.
2. A person can explicitly Summon the Companion and hold a natural OpenAI Realtime Voice Session.

V1 is not a public release. It is a development-signed local app bundle with a persistent Status Menu, launched and supervised from one terminal command. It does not require App Store publication.

## Scope defaults

These defaults close the remaining scope ambiguity:

- Target macOS 15 or newer on Apple Silicon for acceptance testing.
- Build with Swift 6.3 and Xcode 26.6.
- Support exactly one Companion across all connected displays.
- Autonomous roaming remains on one display at a time. Summon or Move to Current Display relocates it.
- Use a local, loopback-only credential broker for the single-user development build.
- Exclude external tester distribution until an authenticated remote broker and Developer ID distribution are designed.
- Exclude persistent Companion Memory from v1. Realtime context exists only for the active Voice Session.

No mission-critical product question remains under these defaults.

## Product boundary

V1 is a Summon-Only Experience and a Screen-Blind Experience.

- The Companion never initiates a Check-in, invitation, greeting, or spoken interaction.
- Roaming Presence is silent movement, not social contact.
- A Voice Session starts only after a click, configurable global shortcut, or Status Menu command.
- The microphone is never used for a wake phrase and is not requested at launch.
- V1 reads display bounds, visible frame, scale factor, pointer position for interaction, and system lifecycle events.
- V1 never captures pixels, enumerates application windows, monitors input activity for availability, inspects app content, or requests Screen Recording, Accessibility, Input Monitoring, Camera, or file access.
- The Companion has no tools and cannot manipulate apps or claim to see the screen.

## Launch and lifecycle

- `./scripts/run` builds the local app bundle, starts the loopback credential broker, launches the bundle executable, and supervises both processes.
- The app has a stable bundle identifier and local development signature so microphone consent remains stable.
- `LSUIElement` and accessory activation make it Dockless.
- An `NSStatusItem` remains present while the process runs, including while the Companion is Parked or Hidden. Apple documents `LSUIElement` as the agent-app setting that removes a Dock presence and `NSStatusItem` as the system menu bar item type.
- The app has no conventional main window. A compact settings panel is allowed.
- A second launch must not create another menu item, Companion, audio engine, or Realtime session.
- Quit from the Status Menu or a terminal interrupt ends voice, releases the microphone, closes all windows, stops the broker, and leaves no process behind.
- The first launch shows Orion in Roaming Presence. Later launches restore safe local interface preferences.

Status Menu commands:

- Summon, changing to End Conversation while voice is active
- Roam, Park, and Hide or Show
- Orion and Athena selection
- Move to Current Display
- Keyboard Shortcut
- Voice, input, and output settings
- Connection and microphone status
- Diagnostics
- Quit

The initial global shortcut is Control + Shift + Space. It is user-configurable and must detect conflicts without requiring Accessibility or Input Monitoring permission.

## Desktop Stage

Use one character-sized transparent, borderless, non-activating `NSPanel` rather than a desktop-sized overlay. The panel follows the character and never takes keyboard focus from the active work app.

- Terrain is the current display's safe visible bounds. Application windows are neither observed nor collision surfaces.
- One Companion exists across every display topology, including negative display coordinates.
- Fresh launch and Summon choose the display containing the pointer.
- Autonomous roaming stays on its current display in v1.
- Move to Current Display or a Summon from another display relocates the Companion through a short edge fade.
- Display removal, rotation, resolution, scale, or arrangement changes recompute bounds and keep the character reachable.
- The Companion keeps a consistent point size across Retina and non-Retina displays.
- Roaming and Park follow the active regular Space without duplication.
- Roaming and Park hide in another app's native full-screen Space. An explicit Summon may reveal the Companion there for the Voice Session.
- Screen lock, screen saver, and sleep hide or pause the Stage. AppKit has no
  public Mission Control lifecycle event, so that transition requires manual
  target-macOS validation and is not an automatic v1 suppression guarantee.
- Sleep or lock ends an active Voice Session. Wake never reopens the microphone or reconnects automatically.

Transparent regions must be genuinely click-through:

- Crop each rendered frame to its alpha bounds while preserving manifest anchors.
- Use a per-frame alpha hit mask with at most 8 points of forgiving padding.
- Toggle panel mouse handling only when the pointer is over an interactive character or bubble region.
- Text selection, scrolling, dragging, resizing, and file drops behind transparent pixels must reach the underlying app unchanged.
- Clicking the character Summons. Dragging repositions it and enters Park.

## Presence and conversation states

Presence has three durable states:

- Roaming: visible, silent, moving in deliberate bursts separated by quiet holds
- Parked: visible and stationary
- Hidden: absent from the Desktop Stage while the Status Menu and Summon remain available

A Voice Session temporarily overlays that state:

- Connecting
- Listening
- Thinking
- Speaking
- Muted
- Error
- Ending

Summon immediately begins connection and settles the character into an attentive pose within 350 milliseconds. Voice setup never waits for a locomotion sequence to finish. Ending restores the previous presence state: Roaming resumes, Park remains parked, and a previously Hidden Companion hides again.

Hide during voice safely ends the session before hiding. A second Summon during voice reveals the current session but never creates another connection.

## Sprite and motion scope

Both existing manifests are authoritative. Each character has 21 states and 64 transparent 512 by 512 PNG frames.

Shared runtime rules:

- Preload and validate every frame, dimension, anchor, frame rate, and referenced state before showing the Companion.
- Update position at display refresh rate while playing sprite frames at manifest-defined rates.
- Align rendered positions to device pixels to prevent shimmer.
- Use a 128-point sprite canvas as the starting visual size.
- Use 150 to 250 millisecond crossfades for unavoidable pose discontinuities.
- Neutral poses represent attention and listening. Happy poses may accompany speech. Angry poses are unused in ordinary v1 conversation.
- During voice, stop autonomous travel and keep an attentive stable pose.
- Switching characters preserves presence and voice state, then grounds the incoming character through a short fade.
- Persist the selected character.
- Respect Reduce Motion by replacing autonomous traversal with a static presence and simple fades.

Orion may:

- Walk left and right
- Enter a display side and climb upward
- Wall cling
- Jump downward
- Land

Orion may not visibly climb down or invent a ledge exit. Climb exits complete behind the display edge.

Athena may:

- Walk left and right
- Take off
- Glide vertically
- Hover
- Land
- Drift slowly while airborne

Athena may not use fast horizontal flight because the assets do not contain it.

V1 adds no sprites, procedural art, mouth animation, or lip synchronization. A real audio-driven waveform beside the conversation bubble communicates listening and speaking.

## Voice experience

Use OpenAI Realtime speech-to-speech over WebRTC. OpenAI recommends WebRTC over WebSockets for client connections because it provides more consistent media performance. The initial configurable model is `gpt-realtime-2.1`; model and voice must remain configuration rather than code constants.

Conversation behavior:

- The person always speaks first after Summon.
- The bubble exposes Connecting, Listening, Thinking, Speaking, Muted, Error, Retry, and End.
- The waveform follows actual input or output audio energy and stops when that audio stops.
- Semantic VAD starts with low eagerness so natural pauses are less likely to be cut off.
- Barge-in is required. New person speech cancels model playback and stale buffered audio.
- No first speech for 60 seconds ends the session.
- Two minutes without speech after conversation begins ends the session.
- Permission denial, broker failure, authentication failure, network loss, rate limiting, peer loss, and audio-device removal leave motion usable and surface a concise nonspoken recovery state.
- A failed or interrupted connection closes the microphone and requires explicit Retry. It never silently resumes listening.
- Missing voice configuration shows Voice Not Configured without disabling the visual Companion.

Privacy behavior:

- Request microphone permission only on the first Summon.
- Stop the microphone on End, Hide, sleep, lock, Quit, unrecoverable network failure, or audio-route failure.
- Never write audio, transcripts, conversation content, or API credentials to disk or logs.
- Do not persist conversation history or Companion Memory.
- Tell the person plainly that the Companion cannot see the screen when asked about visible content.
- Use privacy-redacted structured logs for lifecycle and performance events only.

OpenAI's current data-control table says `/v1/realtime` data is not used for training, has no application-state retention, has 30-day abuse-monitoring retention by default, and is eligible for Zero Data Retention. This provider behavior must be stated accurately in developer diagnostics and any later privacy copy.

## Credential boundary

The standard OpenAI API key never enters the app bundle or app process.

The development launcher starts a minimal Node.js 24 LTS TypeScript broker bound only to `127.0.0.1`:

1. The broker receives `OPENAI_API_KEY` from the terminal environment.
2. The launcher explicitly removes `OPENAI_API_KEY` from the app process environment.
3. The app requests a short-lived Realtime client secret over loopback using a random per-launch bearer.
4. The broker allowlists model, voice, and session configuration and returns only the short-lived secret.
5. The app connects directly to OpenAI over WebRTC, so the broker never proxies or records audio.
6. The broker exposes only health and client-secret endpoints and logs no secret or conversation data.

OpenAI's Realtime WebRTC guidance uses this client-secret pattern to keep standard API keys on a trusted backend. Before sharing V1 with external testers, replace the loopback broker with an authenticated remote deployment using the same interface.

## Technical architecture

Use native Swift because the defining behavior depends on macOS lifecycle, panels, menu bar, Spaces, displays, audio permissions, and pointer interaction.

Stack:

- Swift 6.3 with strict concurrency checking
- Thin Xcode macOS app shell for the `.app`, signing, `Info.plist`, and XCUITest
- Swift Package Manager for internal Modules and pinned external dependencies
- AppKit for lifecycle, Status Menu, panels, displays, Spaces, and system events
- SpriteKit through a transparent `SKView` for animation rendering
- SwiftUI only for the compact settings panel
- A pinned, checksum-verified `stasel/WebRTC` macOS XCFramework release behind the Realtime Adapter
- `KeyboardShortcuts` behind the global shortcut Adapter
- Node.js 24 LTS and TypeScript for the loopback credential broker
- Swift Testing for deterministic behavior and manifest contracts
- XCTest and XCUITest for packaged-app integration and end-to-end behavior
- `swift-format`, broker linting, and all tests as required quality gates

The WebRTC dependency is pinned in `Package.resolved`, never followed from a moving branch. Its release checksum and upstream source provenance must be verified. The Realtime Adapter keeps this community binary replaceable by a self-built upstream framework. The first technical spike must validate capture, playback, echo control, barge-in, and teardown on the target Mac before expanding the implementation.

### Deep Module boundary

`CompanionRuntime` is the highest application Module and the single high behavioral Seam:

```text
CompanionRuntime.send(CompanionCommand)
CompanionRuntime.snapshots -> AsyncStream<CompanionSnapshot>
```

The Interface accepts launch, Summon, end, Roam, Park, Hide, show, drag, character selection, display change, sleep, wake, and Quit. Its snapshot exposes only observable product state: presence, placement, animation, Voice Session state, bubble state, and recoverable error.

Its Implementation hides:

- `PresenceDirector`: presence and restoration state machine
- `MotionDirector`: capability-aware deterministic trajectory and transition planning
- `DesktopStage`: panel placement, displays, Spaces, hit testing, and bubble placement
- `VoiceSession`: microphone lifecycle, Realtime events, interruption, waveform energy, and failure policy
- `Preferences`: non-sensitive local interface configuration

External dependencies sit behind narrow ports with production and deterministic test Adapters:

- `StagePort`: AppKit and SpriteKit Adapter, plus in-memory test Adapter
- `VoiceSessionPort`: OpenAI WebRTC Adapter, plus scripted test Adapter
- `ClientSecretPort`: loopback broker Adapter, plus fake Adapter
- `PlatformPort`: real display and lifecycle events, plus deterministic test Adapter
- `Clock` and `RandomSource`: real and controlled Implementations

The Status Menu, shortcut, and character input Adapters translate person actions into the same `CompanionCommand` values. They own no product state. This keeps logic local to one deep Module and prevents AppKit or OpenAI details from spreading across the codebase.

## Delivery plan

### 1. Vertical technical proof

- Scaffold the signed Dockless app and supervised launcher.
- Show one transparent Orion frame and the Status Menu.
- Prove click-through character hit testing.
- Run one fake Summon state cycle.
- Mint a client secret and complete a WebRTC audio round trip.
- Prove microphone teardown and confirm no unintended permission prompts.

Exit gate: one end-to-end slice proves packaging, rendering, input, credential, and audio feasibility.

### 2. Character runtime

- Implement strict manifest loading and an internal animation gallery.
- Build Orion and Athena capability graphs.
- Add refresh-synchronized motion, anchor handling, easing, holds, crossfades, and alpha hit masks.
- Add golden renders at 1x and 2x.

Exit gate: every legal state and transition passes automated render checks and manual pixel review.

### 3. Desktop Stage and presence

- Implement Roam, Park, drag-to-Park, Hide, Show, and state restoration.
- Add Status Menu, global shortcut, character switching, and Move to Current Display.
- Add connected-display changes, regular Spaces, native full-screen behavior, lock, sleep, and wake.

Exit gate: a one-hour silent roaming session does not speak, request microphone access, steal focus, block clicks, duplicate, disappear irrecoverably, or crash.

### 4. Conversation experience with fakes

- Implement bubble and audio-driven waveform.
- Implement the complete Voice Session state model.
- Add mute, End, Retry, timeout, barge-in, and failure behavior through a scripted Adapter.
- Add screen-blind and no-tools companion instructions.

Exit gate: every voice lifecycle and failure path is deterministic and passes through the same `CompanionRuntime` Interface.

### 5. Live Realtime integration

- Finish the broker and production WebRTC Adapter.
- Tune model, voice, semantic VAD, prompt, input gain, playback, echo handling, and interruption.
- Validate microphone consent, device changes, offline state, rate limits, disconnects, and clean Retry.

Exit gate: a live ten-turn conversation supports natural pauses and barge-in without clipped, repeated, overlapping, or stale audio.

### 6. Polish and release acceptance

- Complete light, dark, busy-background, Retina, scaled-display, Spaces, full-screen, Stage Manager, Reduce Motion, and VoiceOver QA.
- Tune energy, frame pacing, memory, and CPU.
- Run the complete packaged-app end-to-end matrix and two-hour soak.
- Finish developer setup, privacy behavior, diagnostics, and troubleshooting documentation.

Exit gate: every Definition of Done criterion below passes with no flaky test.

## Test strategy

Use one high end-to-end seam through the real app shell and `CompanionRuntime`, replacing Realtime, microphone, display topology, lifecycle events, clock, and randomness with deterministic Adapters. Observe rendered snapshots, accessibility state, menu state, hit testing, and audio lifecycle events.

Required suites:

- Manifest contract tests for every asset, anchor, frame, and transition
- State-machine tests through `CompanionRuntime`
- Golden-frame and transition snapshots at 1x and 2x
- XCUITests for menu, shortcut, click, drag, Roam, Park, Hide, character switch, permission denial, and Quit
- A probe app behind the Companion to verify real click-through behavior
- Deterministic display, Space, full-screen, sleep, wake, and removal scenarios
- Opt-in live OpenAI smoke and human listening tests, excluded from ordinary offline runs
- Manual pixel review on the actual target Mac and external display

Highest-value end-to-end journeys:

1. Clean launch, one menu item, silent Orion, clean Quit.
2. Double launch, still exactly one Companion and one runtime.
3. One-hour work session with no focus theft, blocked clicks, speech, or microphone use.
4. First Summon, macOS consent, ten spoken turns, barge-in, mute, Retry, and End.
5. Permission denial and recovery without losing visual presence.
6. Network loss while Listening, Thinking, and Speaking, followed by clean explicit Retry.
7. Park, drag, Hide, Summon from Hide, End, and restoration to Hidden.
8. Character switch from grounded, climbing, hovering, parked, and conversational states.
9. Mixed-scale displays, negative origins, rearrangement, removal, and Move to Current Display.
10. Space, full-screen, lock, sleep, audio-device change, and Quit during every voice state.

## Definition of Done

Functional:

- One terminal command consistently produces one local app, one Status Menu, and one Companion.
- The Companion appears within 2 seconds after launch on the target Mac.
- Menu, shortcut, and character click can Summon from Roaming, Parked, and Hidden.
- Ending restores the previous presence state.
- No operation requests Screen Recording or any protected permission other than microphone.
- Provider and permission failures never break motion or require an app restart.
- Quit leaves no window, audio engine, broker, menu item, or process.

Motion and visual quality:

- Every allowed Orion and Athena path uses only supported states.
- No frame flash, crop jump, opaque rectangle, alpha halo, moonwalk, one-frame pose reversal, or visible unsupported transition remains.
- Grounded foot-anchor drift is at most 1 point.
- Transparent pixels and padding outside the hit region do not block underlying desktop actions.
- Bubble placement remains inside safe bounds and avoids the character's face, menu bar, and Dock.
- The waveform is refresh-smooth and agrees with real audio state.
- VoiceOver labels, keyboard operation, light and dark appearance, and Reduce Motion pass manual review.

Voice and privacy:

- The microphone is inactive before Summon and closes within 500 milliseconds after End, Hide, sleep, lock, Quit, or failure.
- A normal live exchange lasts at least ten turns and supports barge-in.
- Across 20 controlled turns on stable broadband, response audio starts within 1.5 seconds median and 2.5 seconds at p95 after end of speech.
- Barge-in stops audible Companion speech within 250 milliseconds at p95.
- Natural pauses do not routinely commit turns prematurely.
- No start clipping, end clipping, echo loop, repeated segment, stale buffer, or overlapping old response is audible.
- Audio, transcript, conversation content, standard API key, and client secret never appear in local persistence or logs.
- Asking about the screen produces an honest screen-blind response.

Performance and resilience:

- Idle or Park CPU settles below 2 percent and ordinary roaming below 5 percent on the baseline Apple Silicon Mac.
- Resident memory remains below 200 MB.
- A two-hour soak shows no continuous memory growth, duplicate runtime, lost character, blocked desktop input, or crash.
- Display changes, Space changes, full-screen, sleep, wake, lock, unlock, and audio-route changes leave the Companion reachable and the microphone closed unless a person explicitly starts a new session.
- All automated tests, formatting, and linting pass without flakiness.

## Explicitly out of scope

- App Store submission
- Public or external tester distribution, Developer ID notarization, installer, automatic updates, and launch at login
- Windows, Linux, and Intel Mac acceptance
- Screen Look, screenshots, screen recording, OCR, window inspection, window collision, and screen semantics
- Inactivity monitoring, Presence Signals, Check-in Opportunities, Routine Check-ins, Spontaneous Check-ins, and all proactive contact
- Focus, call, camera, and screen-sharing inference
- Persistent Companion Memory, `memory.md`, personalization, and Memory Compaction
- Stored conversation history, transcripts, audio, text chat, and captions
- Wake phrases and ambient microphone access
- App control, tools, agents, plugins, and work delegation
- New sprites, procedural art, mouth animation, and lip synchronization
- Multiple simultaneous Companions and autonomous cross-display roaming
- Automatic Voice Session recovery after network loss, sleep, or lock
- Accounts, billing, cloud sync, analytics upload, and crash upload
- Offline speech recognition, language model, or speech synthesis

## References

- [Apple LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [Apple NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [Apple SKView transparency](https://developer.apple.com/documentation/spritekit/skview/allowstransparency)
- [OpenAI Realtime with WebRTC](https://developers.openai.com/api/docs/guides/realtime-webrtc)
- [OpenAI Realtime semantic VAD](https://developers.openai.com/api/docs/guides/realtime-vad#semantic-vad)
- [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data#storage-requirements-and-retention-controls-per-endpoint)
- [Node.js release status](https://nodejs.org/en/about/previous-releases)
