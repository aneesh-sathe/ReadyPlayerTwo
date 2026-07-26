# Defer proactive Check-ins to v2

Proactive Check-ins will not ship in v1. The previously resolved Check-in model is preserved as proposed v2 direction because safe availability inference and its privacy boundary need a dedicated design after the summon-only experience is working.

## Preserved v2 direction

- Check-ins remain app-agnostic, social-first, visual before audible, and conservative when availability is uncertain.
- Inactivity begins at five minutes but is evidence rather than permission; timing also requires a Check-in Opportunity.
- Optional Routine and Spontaneous Check-ins share a cadence so invitations do not cluster.
- Focus, calls, camera or microphone use, screen sharing, and native full-screen spaces suppress proactive contact without suppressing Summon.
- Ignored Check-ins retreat after 30 seconds and do not update memory.
- Dismissal reasons provide optional explicit feedback, and learned Check-in Preferences remain local.
- Screen Look is a separate v2 capability, never an implicit Check-in prerequisite, and requires its own security decision.

ADRs 0002, 0004, 0006, and 0007 remain proposed inputs to this v2 design.
