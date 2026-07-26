# Deferred V2 screen and check-in threat-model checklist

## Status

Deferred, unresolved, and not authorized for implementation.

V1 remains summon only and screen blind. This checklist preserves the
questions that must be answered before any screen observation, idle inference,
proactive check-in, learned preference, or Companion Memory work can enter
scope. It does not select an architecture or grant permission to collect data.

Related decisions:

- [ADR 0002: Require explicit screen
  observation](../adr/0002-require-explicit-screen-observation.md)
- [ADR 0008: Auto-update bounded
  memory](../adr/0008-auto-update-bounded-memory.md)
- [ADR 0009: Use backend memory
  compaction](../adr/0009-use-backend-memory-compaction.md)
- [ADR 0012: Defer proactive check-ins to
  V2](../adr/0012-defer-proactive-check-ins-to-v2.md)

## Entry gates

All gates require an explicit security review and a new accepted ADR:

- [ ] Define the exact V2 user value that cannot be met by summon-only,
  screen-blind V1 behavior.
- [ ] Draw the complete data flow for pixels, derived context, activity
  signals, audio, model requests, memory, logs, and deletion.
- [ ] Classify each field before choosing where it is processed or stored.
- [ ] Define explicit opt-in, per-use authority, visible active indication,
  pause, stop, review, reset, and deletion controls.
- [ ] Prove that V2 does not introduce an ambient microphone or wake-word
  listener.
- [ ] Obtain privacy, security, legal, provider-policy, and release-owner
  approval for the selected deployment.
- [ ] Build adversarial tests before enabling any collection in a user build.

## Screen observation questions

- [ ] Is observation person-invoked per use, time bounded, and limited to a
  clearly selected display, window, region, or artifact?
- [ ] What is the minimum raw input needed, and can useful derivation happen
  locally without retaining or transmitting pixels?
- [ ] Which sensitive surfaces must be blocked, including credential prompts,
  password managers, private browsing, notifications, health, finance, HR,
  legal, and private communication?
- [ ] How are hidden windows, other Spaces, multiple displays, transient
  overlays, and full-screen apps excluded?
- [ ] How does the person know exactly what is being observed and when
  observation has ended?
- [ ] Can the person preview and redact the payload before any backend
  transmission?
- [ ] What happens when local classification or redaction is uncertain or
  fails?
- [ ] How are text and instructions visible on screen treated as untrusted
  input resistant to prompt injection and data exfiltration?
- [ ] Which macOS permissions would be required, and can Screen Recording,
  Accessibility, Input Monitoring, Camera, Apple Events, and file access
  remain absent unless individually justified?
- [ ] What raw and derived data survives a successful request, cancellation,
  crash, restart, support bundle, or uninstall?

## Proactive check-in and idle-inference questions

- [ ] What evidence is sufficient to infer availability without inspecting
  content or silently monitoring more input than the person expects?
- [ ] How are reading, presenting, watching, accessibility-device use, remote
  control, long calculations, and away-from-keyboard time distinguished from
  an invitation to interrupt?
- [ ] What are the acceptable false-positive and interruption budgets?
- [ ] How do fixed 15, 30, and 45 minute cadence choices interact with
  inactivity, random timing, quiet hours, meetings, sleep, lock, and full
  screen?
- [ ] Does every retry require the selected cadence to elapse again and the
  person still to satisfy the approved availability policy?
- [ ] How does a check-in retreat after 30 seconds without opening the
  microphone or learning from silence?
- [ ] How can the person disable proactive behavior immediately while
  retaining summon?
- [ ] Which explanation shows why a check-in occurred without revealing or
  retaining sensitive context?

## Learning and memory questions

- [ ] Which facts and dismissal reasons may be learned, and which categories
  are always prohibited?
- [ ] How does explicit feedback distinguish reading from interruption without
  treating a single dismissal as a durable truth?
- [ ] How can the person inspect, edit, delete, pause, export, and reset all
  learned data?
- [ ] What expiry, confidence, contradiction, and correction rules apply to
  Core, Pattern, and Recent Memory?
- [ ] Are the proposed 10,000 character cap, 8,000 character compaction
  threshold, and 6,000 character result still appropriate after privacy
  review?
- [ ] Does backend compaction expose a concentrated personal profile, and what
  consent, provider, retention, access, deletion, and failure rules govern it?
- [ ] Can compaction be tested without sending real personal memory?
- [ ] How are stale, inferred, sensitive, manipulative, or model-injected
  memories prevented from driving behavior?

## Backend and provider questions

- [ ] Which exact payloads leave the device, for which purpose, under which
  credential, and to which allowlisted endpoint?
- [ ] What current provider policies and deployment agreement govern
  processing, retention, training, abuse monitoring, residency, access, and
  deletion?
- [ ] What changes when provider policy, model behavior, endpoint, or contract
  changes?
- [ ] What logs and metrics are necessary, and how are content, credentials,
  identifiers, screenshots, transcripts, and memory excluded or redacted?
- [ ] What incident response, credential rotation, user notification, and
  deletion procedures exist?

## Adversarial verification questions

- [ ] Test credential, banking, health, HR, legal, notification, private
  browsing, and password-manager fixtures.
- [ ] Test prompt injection embedded in documents, images, chat messages,
  spreadsheets, designs, source code, and model output.
- [ ] Test permission denial, revocation, crash, sleep, lock, display changes,
  offline operation, backend failure, and partial deletion.
- [ ] Test that no observation or check-in begins after wake, unlock, relaunch,
  update, or restored state without the approved authority.
- [ ] Test every indicator and stop control against actual capture and network
  state, not only UI state.
- [ ] Verify retained files, preferences, logs, memory, process environments,
  temporary artifacts, and provider-side records against the approved data
  flow.

## Deliberately unresolved

This checklist does not decide:

- Whether V2 should capture screenshots at all.
- Whether derivation, OCR, classification, or redaction should be local or
  remote.
- Which availability signals or autonomous cadence are acceptable.
- Whether Companion Memory should ship.
- Which provider, storage system, permissions, or retention terms to use.

None of these capabilities may be inferred from V1 permissions or implemented
until the entry gates are satisfied.
