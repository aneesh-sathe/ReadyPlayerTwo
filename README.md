# ReadyPlayerTwo

ReadyPlayerTwo is a native macOS Companion that lives across your desktop.
Orion or Athena can roam silently while you work, then join a natural spoken
conversation when you explicitly Summon them.

V1 is local-first, user-invoked, and screen-blind. It never watches your
screen, inspects applications, monitors activity, listens for a wake phrase,
starts a conversation by itself, or saves conversation history.

> **Project status:** The deterministic V1 implementation and no-key packaged
> lifecycle are working. Live voice, accessibility, multi-display, and
> multi-hour release acceptance still require human evaluation on target
> hardware. See the [acceptance ledger](docs/evaluation/v1-acceptance.md).

| Orion | Athena |
| --- | --- |
| ![Orion sprites][orion-preview] | ![Athena sprites][athena-preview] |

[orion-preview]: assets/avatar-orion/preview-expressions.png
[athena-preview]: assets/avatar-athena/preview-expressions.png

## Try it

### Requirements

- Apple Silicon Mac running macOS 15 or newer
- Xcode 26.6 or a compatible newer release
- [Homebrew](https://brew.sh/)
- An OpenAI API key only if you want live voice

Clone the repository, install its command-line dependencies, and check the
machine:

```sh
git clone https://github.com/aneesh-sathe/ReadyPlayerTwo.git
cd ReadyPlayerTwo
brew bundle
./scripts/doctor
```

Start the visual Companion without an API key:

```sh
./scripts/run
```

The launcher builds a locally signed Dockless app, starts a loopback credential
broker, launches one Companion, and supervises both processes. Stop everything
with Control+C in that terminal or Quit in the Status Menu.

### Enable live voice safely

Do not paste a reusable API key into a command that shell history will retain.
Read it without echoing, pass it only to the supervised launcher, then clear the
temporary variable:

```zsh
read -s "rpt_openai_key?OpenAI API key: "
printf '\n'
OPENAI_API_KEY="$rpt_openai_key" ./scripts/run
unset rpt_openai_key
```

For stable microphone consent across rebuilds, provide an installed Apple
Development identity:

```zsh
read -s "rpt_openai_key?OpenAI API key: "
printf '\n'
OPENAI_API_KEY="$rpt_openai_key" \
  RPT_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' \
  ./scripts/run
unset rpt_openai_key
```

Follow the [live voice acceptance protocol](docs/evaluation/live-voice.md) when
evaluating turn-taking, latency, barge-in, device changes, and teardown.

## What you can do

ReadyPlayerTwo launches with Orion in silent Roaming Presence. It has no Dock
icon or conventional main window. The persistent Status Menu remains available
whether the Companion is Roaming, Parked, Hidden, or in a Voice Session.

| Action | How |
| --- | --- |
| Summon or End | Control+Shift+Space, click the Companion, or use the Status Menu |
| Roam | Let the Companion move in deliberate bursts with quiet holds |
| Park | Choose Park or drag the Companion to a reachable position |
| Hide or Show | Clear or restore the Desktop Stage without quitting |
| Change character | Select Orion or Athena without replacing the active session |
| Move displays | Move the single Companion to the display containing the pointer |
| Configure voice | Choose an allowlisted OpenAI voice from the Status Menu |
| Diagnose | Inspect redacted voice, broker, connection, and microphone status |

The first voice Summon requests macOS microphone permission. Launch, Roam,
Park, Hide, Show, character selection, and settings do not request it. The
person always speaks first.

## Privacy model

The local credential broker exists so the reusable OpenAI API key never enters
the app:

```text
Terminal environment -> loopback broker -> OpenAI client-secret endpoint
                              |
                              +-> short-lived secret -> macOS app

macOS app <---------- direct WebRTC audio ----------> OpenAI Realtime
```

| Data or capability | V1 behavior |
| --- | --- |
| Screen content | Never captured, inspected, classified, or transmitted |
| Microphone | Opens only after an explicit Summon |
| Reusable API key | Read only by the loopback broker |
| Voice media | Sent directly between the app and OpenAI |
| Audio and transcripts | Never written to local persistence or logs |
| Conversation history | Kept only for the active session, then discarded |
| Local preferences | Character, presence, shortcut, voice, volume, and safe placement |
| Voice processing | Remote through OpenAI, never described as local |

The broker binds only to `127.0.0.1`, requires a random per-launch bearer,
allowlists session configuration, returns only short-lived credential fields,
and never proxies media.

Read the complete [V1 security boundaries](docs/security/v1-security-boundaries.md).
Screen Look, proactive Check-ins, and Companion Memory are deferred behind the
[V2 threat-model checklist](docs/security/v2-screen-checkin-threat-model.md).

## Architecture

V1 uses native Swift, AppKit, and SpriteKit for the desktop experience, WebRTC
for OpenAI Realtime media, and a small Node.js 24 broker for short-lived
credentials.

| Path | Responsibility |
| --- | --- |
| `Packages/CompanionRuntime` | Product state machine, motion planning, public behavior seam |
| `App/ReadyPlayerTwo` | AppKit lifecycle, Status Menu, SpriteKit stage, settings, voice adapters |
| `App/ReadyPlayerTwoTests` | Hosted integration, visual, privacy, presentation, and adapter tests |
| `App/ReadyPlayerTwoUITests` | Opt-in packaged macOS acceptance journeys |
| `Broker` | Loopback credential minting, allowlisting, redaction, and lifecycle |
| `assets` | Existing Orion and Athena sprite frames and authoritative manifests |
| `scripts` | Doctor, build, test, launch, smoke, and soak entry points |
| `docs` | PRD, ADRs, security boundaries, issue slices, and acceptance evidence |

`CompanionRuntime` is the highest behavioral seam. AppKit controls translate
person actions into runtime commands and render snapshots without owning a
second copy of product state. Platform services, voice, clock, randomness, and
rendering stay behind narrow adapters so ordinary tests remain deterministic.

`project.yml` is the source of truth for XcodeGen. Do not hand-edit or commit
generated changes to `ReadyPlayerTwo.xcodeproj`.

## Develop and verify

| Command | Purpose |
| --- | --- |
| `brew bundle` | Install XcodeGen, Node.js 24, ripgrep, and other tools |
| `./scripts/doctor` | Validate macOS, toolchain, signing, and optional voice configuration |
| `./scripts/run` | Build and supervise one local app and broker |
| `./scripts/test` | Run privacy scans, formatting, shell, runtime, broker, build, and AppKit tests |
| `./scripts/smoke` | Exercise the real no-key packaged lifecycle and exact process cleanup |
| `./scripts/soak` | Run the default two-hour no-key resource and lifecycle soak |

Run the authoritative deterministic gate before committing:

```sh
./scripts/test
```

Run the real no-key lifecycle after changes to launch, packaging, broker,
permissions, singleton behavior, or cleanup:

```sh
./scripts/smoke
```

Use a short soak only to validate the harness, immediate memory ceiling, and
cleanup:

```sh
RPT_SOAK_DURATION_SECONDS=15 ./scripts/soak
```

Runs shorter than 180 seconds do not prove settled CPU or continuous RSS
stability. Full acceptance needs separate two-hour Roaming and Park runs. For
Park, choose it manually within the 120-second warm-up:

```sh
RPT_SOAK_EXPECTED_PRESENCE=park ./scripts/soak
```

Current results, exact limitations, and remaining human gates live in the
[V1 acceptance ledger](docs/evaluation/v1-acceptance.md).

## Agent quick start

Coding agents should orient themselves in this order:

1. Read [CLAUDE.md](CLAUDE.md) for verified commands, pitfalls, and durable
   project rules.
2. Read [CONTEXT.md](CONTEXT.md) for the shared domain vocabulary.
3. Read the relevant decisions under [`docs/adr`](docs/adr).
4. Read the [V1 PRD](docs/prd/v1.md) and
   [acceptance ledger](docs/evaluation/v1-acceptance.md).
5. Check the matching GitHub issue and every acceptance criterion before
   changing code.

Non-negotiable V1 invariants:

- Keep V1 Summon-only and screen-blind.
- Never add ambient microphone, screen capture, window inspection, inactivity
  monitoring, proactive Check-ins, or persistent Companion Memory.
- Never put `OPENAI_API_KEY` in the app, product source, persistence, or logs.
- Use only the supplied Orion and Athena sprites. Do not add mouth animation or
  promise lip synchronization.
- Keep exactly one Companion and one high runtime state seam.
- Treat `project.yml` as authoritative and generated Xcode project files as
  disposable.
- Test behavior through public interfaces using one RED-GREEN tracer bullet at
  a time.
- Preserve unrelated worktree changes and commit each independent change
  atomically.
- Do not close an issue until every acceptance criterion has reproducible
  evidence.

Preferred change loop:

1. Define the observable behavior and success condition.
2. Add one failing public-interface test.
3. Implement the smallest behavior that makes it pass.
4. Refactor only while green.
5. Run `./scripts/test`, plus `./scripts/smoke` when lifecycle behavior changed.
6. Record durable commands, decisions, and pitfalls in `CLAUDE.md`.
7. Update acceptance evidence without treating scripted tests as live or
   manual results.

Issue tracker conventions and triage labels are documented under
[`docs/agents`](docs/agents).

## Product contract and roadmap

- [V1 PRD](docs/prd/v1.md)
- [V1 scope plan](docs/v1-scope-plan.md)
- [Tracer-bullet issue slices](docs/issues/v1-slices.md)
- [Architecture decisions](docs/adr)
- [V1 acceptance evidence](docs/evaluation/v1-acceptance.md)
- [GitHub issues](https://github.com/aneesh-sathe/ReadyPlayerTwo/issues)

V1 proves desktop-wide character dynamics and explicitly summoned voice.
Proactive Check-ins, screen context, and bounded local Companion Memory remain
preserved as V2 design work, not hidden V1 capabilities.

## Troubleshooting

### Voice Not Configured

Visual presence works without an API key. To use voice, stop the launcher and
restart it with `OPENAI_API_KEY` present only in that terminal process.

### Microphone permission repeats after rebuilding

Ad hoc signatures can change identity between builds. Install a trusted Apple
Development identity and set `RPT_SIGNING_IDENTITY` for a stable local identity.

### Microphone permission was denied

Enable ReadyPlayerTwo under System Settings, Privacy & Security, Microphone,
then explicitly Summon again. The app never retries silently.

### ReadyPlayerTwo is already running

The launcher enforces a singleton. Stop the original terminal with Control+C or
choose Quit from its Status Menu, then run again.

### Xcode reports an outdated CoreSimulator

The warning does not block the macOS build or tests. V1 has no simulator
dependency.

### Packaged UI tests stop before execution

The `ReadyPlayerTwoPackagedAcceptance` scheme requires macOS UI-automation
authorization and is more reliable with a trusted signed runner. An
authorization failure is not a product test result.
