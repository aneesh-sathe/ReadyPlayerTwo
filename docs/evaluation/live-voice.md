# Live voice acceptance protocol

This protocol validates the parts of ReadyPlayerTwo V1 that deterministic
Adapters cannot prove: microphone consent, acoustic playback, natural
turn-taking, audible barge-in, device changes, network recovery, and real
OpenAI Realtime latency.

The protocol is pending until a target Mac, a trusted signing identity, an
OpenAI API key, microphone access, speakers or headphones, and a human listener
are available. Compiling the voice path or passing scripted tests is not a live
voice result.

## Protect the evaluation key

Do not paste an API key into a command that will be retained in shell history.
Read it into a temporary zsh variable without echoing it, pass it only to the
supervised launcher, and clear the variable after the launcher exits:

```zsh
read -s "rpt_openai_key?OpenAI API key: "
printf '\n'
OPENAI_API_KEY="$rpt_openai_key" \
  RPT_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' \
  ./scripts/run
unset rpt_openai_key
```

Use a least-privileged project key intended for this local evaluation. Never
copy the key, bearer, ephemeral client secret, transcript, or spoken content
into an evaluation result.

## Preconditions

- Run on Apple Silicon with macOS 15 or newer.
- Use a trusted local signing identity so microphone consent survives rebuilds.
- Use stable broadband and begin with headphones to separate application
  behavior from speaker echo.
- Close any other ReadyPlayerTwo launcher before starting.
- Record only timing values, state names, and pass or fail observations.
- Confirm the Status Menu reports remote OpenAI processing before Summon.

## One-round-trip feasibility

1. Launch and wait for Orion or Athena plus the Status Menu.
2. Confirm the macOS microphone indicator is off before Summon.
3. Summon from the Status Menu and approve microphone access if prompted.
4. Confirm the Companion does not greet first.
5. Speak one short request, hear one intelligible spoken response, and choose
   End.
6. Confirm the bubble closes and the macOS microphone indicator turns off
   within 500 milliseconds.
7. Quit and confirm the launcher, app, and broker all exit.

Do not continue to conversational evaluation if any feasibility step fails.

## Ten-turn conversation

Hold one conversation for at least ten user turns. Include a short answer, a
long answer, a correction, a two-second natural pause, Mute and explicit
Unmute, and two interruptions while the Companion is speaking.

Pass only if:

- the person always speaks first;
- natural pauses do not routinely end a turn early;
- no response is clipped, repeated, overlapped, or replayed after interruption;
- the bubble and waveform match what is audible;
- Mute suppresses input until explicit Unmute;
- End closes the microphone and restores the prior presence state.

## Controlled latency

Collect 20 response-latency samples on the same stable connection. For each
turn, measure from the end of user speech to the first audible response sample.
Record milliseconds only.

Sort the 20 values. The median is the mean of values 10 and 11. The nearest-rank
p95 is value 19. Pass when the median is at most 1,500 milliseconds and p95 is
at most 2,500 milliseconds.

| Turn | Response start, ms |
| ---: | ---: |
| 1 | Pending |
| 2 | Pending |
| 3 | Pending |
| 4 | Pending |
| 5 | Pending |
| 6 | Pending |
| 7 | Pending |
| 8 | Pending |
| 9 | Pending |
| 10 | Pending |
| 11 | Pending |
| 12 | Pending |
| 13 | Pending |
| 14 | Pending |
| 15 | Pending |
| 16 | Pending |
| 17 | Pending |
| 18 | Pending |
| 19 | Pending |
| 20 | Pending |

## Controlled barge-in

Collect 20 interruption samples while the Companion is audibly speaking.
Measure from the first detected user interruption to audible playback silence.
Record milliseconds only. Sort the results and use value 19 as nearest-rank
p95. Pass when p95 is at most 250 milliseconds and no stale buffered segment
plays afterward.

## Recovery matrix

Exercise each condition in a fresh supervised launch when isolation is useful:

| Condition | Required observation |
| --- | --- |
| Microphone denied | A nonspoken recoverable error explains the System Settings path; visual controls remain usable. |
| Network removed during Listening | Capture and playback close, no automatic reconnect occurs, and Retry is explicit. |
| Network removed during Speaking | Audible output and capture close without stale replay after recovery. |
| Default input changed | The session ends with an audio-route error and requires Retry. |
| Default output changed | The session ends with an audio-route error and requires Retry. |
| Same-device input source changed | The session ends with an audio-route error and requires Retry. |
| Same-device output source changed | The session ends with an audio-route error and requires Retry. |
| Sleep or screen lock | The session ends, and wake or unlock does not reopen the microphone. |
| Broker stopped | The supervised launcher closes the app and reports failure without leaving children. |

After every row, verify Roam, Park, Hide or Show, Companion selection,
diagnostics, Retry when offered, End, and Quit remain usable.

## Result record

Record the date, macOS version, Mac model, signing identity class, selected
Realtime model and voice, network type, output route, aggregate latency values,
aggregate barge-in values, and pass or fail for each checklist. Do not record
conversation content or credentials.

Until that record exists, GitHub issues whose acceptance criteria require live
voice remain open and must not be described as complete.
