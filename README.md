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

To enable voice for that launch, read the key without echoing it or retaining
it in shell history, provide it only to the supervised launcher, and clear the
temporary variable afterward:

```zsh
read -s "rpt_openai_key?OpenAI API key: "
printf '\n'
OPENAI_API_KEY="$rpt_openai_key" ./scripts/run
unset rpt_openai_key
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

Run the real packaged lifecycle smoke without an OpenAI key:

```sh
./scripts/smoke
```

The smoke command builds through `./scripts/run`, launches the signed Dockless
app and loopback broker, rejects a duplicate launch, audits macOS TCC events for
unexpected microphone access, then interrupts the launcher and confirms its
exact captured app and broker processes exited. Stop any existing launcher
before running it. The command deliberately does not Summon, so it does not
validate microphone consent or live OpenAI voice.

Run the default two-hour no-key resource and lifecycle soak:

```sh
./scripts/soak
```

The soak uses the real supervised launcher and monitors only its exact reported
launcher, app, and broker processes. It fails on process death, broken lineage,
a persistent unexpected child, combined resident memory at or above 200 MiB,
or continuous RSS growth. After a 120-second warm-up, a 12-sample rolling
window also enforces combined CPU below 5 percent for ordinary Roaming
Presence.

Use a validated duration from 1 through 86400 seconds for a short harness check:

```sh
RPT_SOAK_DURATION_SECONDS=15 ./scripts/soak
```

Runs shorter than 180 seconds validate lifecycle, metric collection, resident
memory, and teardown. They do not prove settled CPU, continuous RSS stability,
or the two-hour acceptance criterion.

To evaluate the 2 percent Park CPU ceiling, declare the expected presence and
manually choose Park from the Status Menu within the 120-second warm-up:

```sh
RPT_SOAK_EXPECTED_PRESENCE=park ./scripts/soak
```

The harness cannot change or verify Park without macOS UI automation
authorization, so this remains an operator-controlled test. The soak never
Summons, removes `OPENAI_API_KEY`, stores no metrics report, and emits only
process resource summaries.

Live voice quality, microphone consent, multi-display behavior, and visual
polish still require testing on the target Mac. Follow the
[live voice acceptance protocol](docs/evaluation/live-voice.md) for
history-safe key entry, trusted signing, controlled latency and barge-in
measurement, route changes, recovery, and teardown.

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
