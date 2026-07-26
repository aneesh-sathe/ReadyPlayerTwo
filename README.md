# ReadyPlayerTwo

ReadyPlayerTwo is a local macOS Companion prototype. Orion or Athena can roam
silently across the desktop, and a person can explicitly Summon a live
conversation powered by OpenAI Realtime.

V1 is intentionally user-invoked and screen-blind. It does not capture the
screen, inspect applications, monitor activity, listen for a wake phrase,
initiate conversations, or retain conversation history.

## Requirements

- Apple Silicon Mac running macOS 15 or newer
- Xcode 26.6 or a compatible newer release
- Homebrew
- An OpenAI API key for live voice

Install the command-line dependencies and verify the machine:

```sh
brew bundle
./scripts/doctor
```

## Run

Visual presence works without an OpenAI API key:

```sh
./scripts/run
```

To enable voice for that launch, provide the key only to the supervised
launcher:

```sh
OPENAI_API_KEY="your-key" ./scripts/run
```

The launcher builds a locally signed app, starts a loopback credential broker,
and supervises both processes. Press Control+C in the launching terminal or
choose Quit from the Status Menu to stop the app and broker.

The default global Summon shortcut is Control+Shift+Space. The Status Menu can
also Summon or end a conversation, Roam, Park, Hide or Show, switch between
Orion and Athena, move the Companion to the current display, mute voice, and
show redacted diagnostics.

The first voice Summon requests macOS microphone permission. Launch, movement,
presence controls, and character selection do not request it.

## Privacy boundary

- The reusable OpenAI API key remains in the loopback broker process.
- The macOS app receives only a short-lived Realtime client secret.
- Voice media travels directly between the app and OpenAI over WebRTC.
- The broker does not proxy audio.
- The app writes no audio, transcripts, conversation content, client secrets,
  or conversation memory to disk.
- Only interface preferences such as character, presence, shortcut, voice, and
  safe placement are stored locally.
- Voice processing is remote, not local.

See [V1 security boundaries](docs/security/v1-security-boundaries.md) and the
[deferred V2 threat-model checklist](docs/security/v2-screen-checkin-threat-model.md)
when those designs are being evaluated. The complete product contract is in
[the V1 PRD](docs/prd/v1.md).

## Test

Run the deterministic privacy, formatting, package, broker, build, and app test
gates:

```sh
./scripts/test
```

Live voice quality, microphone consent, multi-display behavior, and visual
polish still require testing on the target Mac. A trusted local signing identity
is recommended for stable microphone permission across rebuilds:

```sh
RPT_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" \
  OPENAI_API_KEY="your-key" \
  ./scripts/run
```

## Troubleshooting

If voice reports that it is not configured, stop the launcher and start it
again with `OPENAI_API_KEY` present in that terminal.

If microphone permission was denied, enable ReadyPlayerTwo in System Settings
under Privacy & Security, then explicitly Summon again.

If microphone permission is repeatedly requested after rebuilds, use a trusted
local signing identity through `RPT_SIGNING_IDENTITY`. Ad hoc signatures can
change identity between builds.

If a prior launcher is active, a second `./scripts/run` exits without creating
another Companion. Stop the original terminal process or use the Status Menu
Quit command.
