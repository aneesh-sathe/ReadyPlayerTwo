# Desktop Companionship

This context defines a voice-first character that provides socially natural company across a person's desktop.

## Core experience

**Companion**:
A character that provides socially natural spoken company while a person works at their desktop.
_Avoid_: Assistant, chatbot, desktop pet

**Work Session**:
A period in which a person uses their desktop to pursue work, regardless of profession or application.
_Avoid_: Agent session, app session

**Summon-Only Experience**:
An interaction model in which the person initiates every conversation, while the Companion may remain visibly present and move without initiating contact.
_Avoid_: Reactive mode, manual mode

**Screen-Blind Experience**:
A Companion experience that receives no visible content or semantic information from the desktop. Knowing the Desktop Stage's physical bounds does not count as observing the screen.
_Avoid_: Local screen processing, passive context

**Roaming Presence**:
The Companion's default out-of-conversation state, in which it remains visible and moves silently without initiating contact.
_Avoid_: Check-in, idle animation

**Park**:
A person-directed state in which the Companion remains visible at a fixed location without moving autonomously.
_Avoid_: Pause, pin

**Hide**:
A person-directed state in which the Companion leaves the Desktop Stage while the Status Menu remains available and a later Summon remains possible.
_Avoid_: Quit, disable

**Summon**:
A person-initiated request for the Companion's attention that may happen at any time.
_Avoid_: Check-in, wake-up, trigger

**Summoned Conversation**:
A user-led exchange that begins after a Summon and follows the person's intent.
_Avoid_: Check-in Conversation

**Voice Session**:
A live spoken exchange whose microphone access begins only after the person intentionally starts an interaction.
_Avoid_: Ambient listening, voice mode

**Desktop Stage**:
The desktop-wide area in which a Companion can appear and move independently of any single application window.
_Avoid_: Overlay, canvas, companion window

**Status Menu**:
The Companion's persistent macOS menu bar control surface for Summon, presence controls, avatar and voice preferences, and Quit. It remains available while the process runs, including when the Companion is Parked or Hidden.
_Avoid_: Top bar, tray app, main window

## Deferred memory design

**Companion Memory**:
A local, user-auditable record of learned preferences, quirks, and personal context that helps the Companion become more relevant over time.
_Avoid_: Chat history, transcript, model context

**Memory Budget**:
The hard character limit on Companion Memory that forces deliberate retention, consolidation, and removal of outdated knowledge.
_Avoid_: Token limit, storage quota

**Core Memory**:
Stable identity, values, relationships, and important personal facts retained until contradicted or deleted.
_Avoid_: Permanent memory

**Pattern Memory**:
Learned preferences and quirks whose strength changes as supporting behavior repeats or becomes outdated.
_Avoid_: Behavioral profile

**Recent Memory**:
Temporary projects, concerns, and conversational context that expires or is summarized before longer-lived memory.
_Avoid_: Chat history, session log

**Memory Compaction**:
LLM-assisted consolidation that preserves the most useful knowledge while bringing Companion Memory back within its Memory Budget.
_Avoid_: Truncation, cleanup

## Deferred proactive experience

**Inactivity**:
An interval of at least five minutes without desktop input. It is evidence that a person may be taking a break, not proof that they are available.
_Avoid_: Break, idle user

**Check-in Opportunity**:
An inferred moment during a Work Session when a Check-in is unlikely to interrupt active work.
_Avoid_: Idle event, trigger

**Agent Wait**:
The interval after a person delegates work to an AI agent and before that work completes. It is one possible source of a Check-in Opportunity.
_Avoid_: Downtime, idle time

**Check-in**:
A Companion-initiated invitation to have a brief conversation at a Check-in Opportunity. It attracts attention visually, does not begin speaking until the person responds, and retreats after 30 seconds when ignored.
_Avoid_: Notification, interruption, wake-up

**Routine Check-in**:
A Check-in that becomes eligible on a person-selected recurring cadence of 15, 30, or 45 minutes, then waits for a Check-in Opportunity. It may recur on that cadence during continued Inactivity.
_Avoid_: Alarm, scheduled interruption

**Spontaneous Check-in**:
A separately enabled Check-in whose timing is varied by the Companion rather than tied to a fixed cadence, while still requiring a Check-in Opportunity.
_Avoid_: Random check-in, agent check-in

**Check-in Conversation**:
A Companion-led, social-first exchange that begins when a person accepts a Check-in.
_Avoid_: Assistance session, coaching

**Dismissal Reason**:
An optional explanation a person gives after declining a Check-in, such as reading, meeting, or poor timing.
_Avoid_: Feedback form, rejection reason

**Check-in Preference**:
An explicit or learned tendency governing when and how a person wants the Companion to initiate Check-ins.
_Avoid_: User profile

**Presence Signal**:
Content-free information used to estimate whether a Check-in would be non-disruptive, such as the duration of Inactivity.
_Avoid_: Screen context, user context

**Check-in Suppression**:
A condition that prohibits proactive Check-ins without preventing the person from summoning the Companion.
_Avoid_: Disable, offline mode

**Screen Look**:
A one-time observation of visible desktop content that the person explicitly requests and can clearly see is occurring.
_Avoid_: Screen recording, ambient access, passive capture
