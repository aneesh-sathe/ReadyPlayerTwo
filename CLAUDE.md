# Project Guidance

## Atomic Commits

- Commit every independently complete change before starting the next change.
- Keep each commit focused on one behavior, refactor, documentation update, or test cycle.
- Never combine unrelated changes in a commit.

## V1 Product

- The first shippable release targets macOS only.
- The product is a voice-first, app-agnostic desktop Companion for people in any profession.
- Ship v1 as a locally built macOS app bundle that does not require App Store publication.
- Provide one terminal command that builds, launches, and supervises the local app and credential broker during development.
- Quit from the Status Menu or interrupting the development launcher must stop the app, Voice Session, microphone, windows, and broker without orphaned processes.
- Run as a Dockless agent app and keep a persistent Status Menu in the macOS menu bar.
- The Status Menu owns Summon or End Conversation, Roam, Park, Hide or Show, avatar selection, voice settings, and Quit.
- V1 has no conventional main window. A compact settings popover is allowed.
- V1 is a Summon-Only Experience. The Companion never initiates a Check-in.
- V1 is a Screen-Blind Experience. Do not capture, inspect, OCR, classify, or transmit screen content.
- Desktop Stage geometry needed to place and move the character is not screen observation.
- V1 does not monitor Inactivity, evaluate Check-in Opportunities, run proactive timing, or use Presence Signals.
- Roaming Presence is the default v1 state: the Companion remains visible and moves silently without initiating contact.
- Park keeps the Companion visible at a fixed location, while Hide removes it from the Desktop Stage without disabling Summon.
- The person may Summon the Companion through a configurable global keyboard shortcut, the Companion, or its menu-bar item.
- Every v1 conversation is a user-led Summoned Conversation that follows the person's intent.
- Never keep the microphone open to detect a spoken wake phrase.
- Start microphone access only after a Summon.
- Use OpenAI's Realtime API for low-latency speech-to-speech Voice Sessions.
- Keep the exact Realtime model and voice configurable.
- The Companion inhabits a desktop-wide Desktop Stage rather than being confined to an application.
- Treat display geometry as terrain. Application windows and their contents are neither observed nor collision surfaces.
- Keep the Companion UI click-through outside the visible character and conversation controls.
- Summon may explicitly reveal the Companion in a native full-screen space.
- The Companion is not a general assistant, chatbot, or desktop pet.
- V1 prioritizes polished character motion and natural Realtime voice behavior.
- V1 does not persist audio, transcripts, conversational history, or Companion Memory.
- Keep only the context needed for the active Voice Session, then discard it when the session ends.

## V2 Proactive Check-in Design

- Preserve this section as proposed v2 direction. None of it authorizes proactive behavior in v1.
- The intended promise is company during non-disruptive pauses in a Work Session.
- Agent Wait is one possible source of a Check-in Opportunity, not the product's sole use case.
- Never initiate a Check-in while the person is actively working.
- Inactivity is a Presence Signal that may indicate a break, but it does not prove availability.
- Use five minutes without keyboard or pointer input as the initial minimum Inactivity threshold.
- Learned preferences may lengthen the Inactivity threshold but must not shorten it automatically.
- When availability is uncertain, remain silent. Inactivity alone must never trigger a Check-in.
- Do not require a user-defined availability schedule.
- Let the person optionally choose a Routine Check-in cadence of 15, 30, or 45 minutes.
- Treat Routine Check-in cadence as eligibility, not an alarm.
- A due Routine Check-in waits for the next safe Check-in Opportunity, and missed intervals never stack.
- During continued Inactivity, an ignored Routine Check-in may recur after the full selected cadence if no Check-in Suppression applies.
- Use Spontaneous Check-ins alongside Routine Check-ins.
- Require explicit opt-in for Spontaneous Check-ins, separately from Routine cadence.
- Routine and Spontaneous Check-ins share one cadence clock.
- Any proactive Check-in resets the shared cadence so invitations never cluster.
- Neither Routine nor Spontaneous timing may bypass Check-in Opportunity safeguards.
- Treat macOS Focus and Do Not Disturb as absolute Check-in Suppressions.
- Treat an active call, external microphone or camera use, and screen sharing as absolute Check-in Suppressions.
- Use only content-free system activity signals for call and screen-sharing suppression.
- Hide the Companion and suppress proactive Check-ins in native full-screen spaces.
- Check-in Suppression never prevents Summon.
- Initiate a Check-in visually, with an optional subtle sound.
- A Check-in must not speak aloud until the person responds.
- An ignored Check-in retreats automatically after 30 seconds.
- Ignoring a Check-in must not update Companion Memory.
- Check-in Conversations are Companion-led and social-first.
- Dismissing a Check-in is immediate and reveals an optional Dismissal Reason dropdown.
- A dismissal without a reason is only a weak Check-in Preference signal.
- Never infer the reason for dismissal by silently inspecting screen content.
- Keep learned Check-in Preferences on the person's Mac.
- Do not sync Check-in Preference history or send it to the backend.

## V2 Screen Look Design

- Screen Look and every other use of visible desktop content are excluded from v1.
- Screen Look remains a proposed, person-invoked v2 capability.
- Screen Look is a separate capability from proactive Check-ins and is not required to infer a Check-in Opportunity.

## Deferred Memory Design

- Companion Memory is excluded from v1 and remains proposed future work.
- `memory.md` is the proposed local representation of Companion Memory.
- Companion Memory updates automatically from interactions and is not limited to explicit "remember this" requests.
- Companion Memory may retain sensitive personal facts when they are relevant.
- Companion Memory has three tiers: Core Memory, Pattern Memory, and Recent Memory.
- Preserve Core Memory until contradicted or deleted, weaken outdated Pattern Memory, and expire or summarize Recent Memory first.
- Enforce a hard character-based Memory Budget so irrelevant or outdated knowledge must be consolidated or removed.
- Cap the complete `memory.md` file at 10,000 characters, start compaction at 8,000, and require compaction to reduce it below 6,000.
- Use a backend LLM for Memory Compaction when the Memory Budget is reached.
- Backend Memory Compaction transmits the full sensitive `memory.md`; consent, retention, training use, encryption, and deletion remain unresolved security requirements.
- The Memory Budget controls relevance and size, not privacy. Treat the entire file as sensitive data.

## Security

- Complete a focused voice data-flow review before shipping the OpenAI Realtime integration.
- Never embed a standard OpenAI API key in the local app.
- Use a stateless credential broker to mint short-lived Realtime client secrets.
- Connect the local app directly to OpenAI Realtime so the broker does not proxy conversation audio.
- Probe voice readiness once at launch with an unauthenticated, body-free GET to
  the strict loopback broker `/health` endpoint. Reject redirects and never use
  this probe to contact OpenAI.
- Keep the Status Menu disclosure explicit that OpenAI processes voice remotely.
- Do not request Screen Recording permission or link screen-capture behavior in v1.
- The dedicated Screen Look and proactive Check-in threat models are deferred with their v2 designs.
- Continuous or silent screen observation is prohibited.
- Any future Screen Look requires an explicit user request and an unmistakable active indicator.
- Review capture permissions, data minimization, sensitive-data redaction, retention, model-provider handling, encryption, consent indicators, and prompt injection before adding screen context.

## V1 Technical Architecture

- Target macOS 15 or newer on Apple Silicon for v1 acceptance.
- Use Swift 6.3 with a thin Xcode app shell and Swift Package Manager Modules.
- Use AppKit for lifecycle, the Status Menu, panels, displays, Spaces, and system events.
- Use SpriteKit in a transparent `SKView` for character rendering.
- Limit SwiftUI to compact settings UI.
- Use a pinned macOS WebRTC XCFramework behind a Realtime Adapter.
- Use a Node.js 24 LTS TypeScript broker bound to loopback for short-lived Realtime credentials.
- Remove `OPENAI_API_KEY` from the app process environment when the launcher starts it.
- Make `CompanionRuntime` the high behavioral Seam with a command Interface and observable snapshots.
- Keep AppKit, SpriteKit, OpenAI Realtime, the credential broker, platform events, clock, and randomness behind production and deterministic test Adapters.
- Support one Companion across connected displays. Autonomous roaming stays on one display; Summon or Move to Current Display relocates it.
- Use a 128-point sprite canvas as the initial visual scale and device-pixel-align movement.
- Store only local interface preferences such as character, presence mode, shortcut, voice, volume, and safe position.
- AppKit exposes no public Mission Control start or end notification. Treat public active Space changes as placement refreshes only and never synthesize Mission Control lifecycle events.

## Verified Development Environment

- macOS 26.5 on Apple Silicon.
- Xcode 26.6 with Apple Swift 6.3.3.
- XcodeGen 2.46.0 is installed.
- Use Node.js 24.18.0 from `/opt/homebrew/opt/node@24/bin`; the globally linked Node.js is not the broker target.

## Verified Commands

- `./scripts/doctor` validates the local toolchain, signing, broker, and optional voice configuration without printing secrets.
- `./scripts/test` runs privacy scans, formatting, runtime tests, broker tests, XcodeGen, the packaged build, and AppKit tests.
- `./scripts/run` is the supervised local launch seam for the app and loopback broker.
- `./scripts/smoke` runs the real no-key packaged launcher and verifies signed Dockless launch, loopback broker health, duplicate rejection, no launch-time microphone request, and exact-PID interrupt cleanup.
- `./scripts/soak` defaults to a 7200-second no-key run through the supervised launcher. `RPT_SOAK_DURATION_SECONDS` accepts 1 through 86400 for shorter checks.
- The soak enforces combined resident memory below 200 MiB immediately. After a 120-second warm-up, it enforces a 12-sample combined CPU ceiling of 5 percent for Roaming or 2 percent for an operator-declared Park run, plus deterministic continuous RSS growth checks.
- `RPT_SOAK_EXPECTED_PRESENCE=park` selects the Park CPU policy but cannot change or verify presence. The operator must choose Park manually within the warm-up.
- Five-second and ten-second no-key soak checks passed on this Mac with exact-PID teardown. No two-hour soak has been executed yet.
- `RPT_LIFECYCLE_REPORT_PATH` is a test-only launcher seam that writes an owner-only PID report. Never add credentials, endpoints, or user data to it.
- The authoritative Swift format path discovery includes `App/ReadyPlayerTwoUITests`.
- `project.yml` is the Xcode project source of truth. Never commit or hand-edit `ReadyPlayerTwo.xcodeproj`.
- The current machine has no trusted Apple Development identity. Ad hoc signing builds and runs locally, but microphone consent may need to be granted again after rebuilds.
- Xcode may report an outdated CoreSimulator framework while macOS builds and tests still pass. V1 does not require a simulator.
- `ReadyPlayerTwoPackagedAcceptance` is the opt-in XCUITest scheme. Its `build-for-testing` action compiles under ad hoc signing.
- Packaged acceptance uses the exact Debug-only `-ReadyPlayerTwoPackagedAcceptance` argument, isolated clean preferences, no global shortcut, no platform monitor, and fixed not-configured voice readiness.
- This Mac stops XCUITest before test execution with LocalAuthentication code -2. Grant macOS UI-automation authorization or use a trusted signed runner to execute the opt-in suite.

## Agent skills

### Issue tracker

Issues and PRDs live in GitHub Issues for `aneesh-sathe/ReadyPlayerTwo`. External pull requests are not a triage request surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Map canonical triage roles to the repository's existing GitHub labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository with one root glossary and system-wide ADR directory. See `docs/agents/domain.md`.

## Assets

- V1 must use the existing sprite files without adding new character art.
- `assets/avatar-orion` contains a grounded warrior with walking, climbing, jumping, wall-clinging, landing, direction, and emotion sprites.
- `assets/avatar-athena` contains an angel with walking, flying, hovering, landing, direction, and emotion sprites.
- Both avatars use transparent 512 by 512 PNG frames and provide animation manifests.
- Neither avatar currently has talking, listening, thinking, greeting, breathing-idle, or sleep sprites.
- Athena lacks horizontal flight sprites.
- Orion lacks climb-down and ledge-exit transition sprites.
- Do not add mouth animation or promise lip synchronization in v1.
- Show an animated waveform beside the conversation bubble during spoken output.
- Restrict Orion to walking, upward climbing, wall clinging, jumping down, and landing. Hide climb exits behind display edges.
- Restrict Athena to grounded horizontal walking, vertical gliding, hovering, takeoff, and landing. Use only slow hover drift for airborne horizontal motion.
- Bridge unavoidable pose discontinuities with short runtime crossfades or occlusion behind the conversation bubble.
