# Re:Link — Onboarding Flow Specification

This document describes the first-launch onboarding experience for Re:Link. It covers
the purpose of each screen, the content it presents, the actions available to the user,
and the transitions between screens. It is intended as a reference for implementation,
not a pixel-precise design spec.

---

## Overview

The onboarding flow runs once, on first launch, before the user reaches the main pairing
screen. Its job is threefold: explain why Re:Link works the way it does, collect the two
pieces of configuration required to function (server address and ICE settings), and
establish the SAS verification habit before the user's first real session.

The flow has six screens. Screens 1 and 2 are conceptual; screens 3 and 4 collect
configuration; screen 5 explains SAS verification; screen 6 confirms the setup is
complete.

A progress indicator at the top of each screen shows position in the flow. Users can
navigate backwards freely. A skip path on the welcome screen allows experienced users
to jump directly to server configuration.

---

## Screen 1 — Welcome

**Purpose.** First contact. State what Re:Link is and what it guarantees before asking
for anything.

**Content.**

The screen presents the product name and a short statement of the trust model: no
accounts, no cloud storage, no persistent records. The relay server coordinates
connections but never reads data. Each of these three properties is listed as a
concrete fact, not a feature claim.

Two actions are available:

- **Get started** — proceeds to screen 2 (How it works).
- **I know what I'm doing — skip to setup** — proceeds directly to screen 3 (Server
  config), marking screens 2 through 4 of the progress indicator as implicitly
  complete. This path is for users re-configuring after a reinstall or setting up a
  second device.

**Design notes.** No illustrations, no animated hero. The value of Re:Link is stated
plainly. The skip path must be visually subordinate to the primary action — it should
not be the first thing a new user reaches for.

---

## Screen 2 — How it works

**Purpose.** Explain the blind relay model and the key properties a user needs to
understand before their first session. This screen is the reason SAS verification makes
sense to users when they encounter it later.

**Content.**

A short diagram or illustration shows the relay server sitting between two devices
during pairing, then stepping out once the connection is live. The accompanying text
makes three points:

1. The relay matches two devices and then plays no further role. A seized or
   compromised relay cannot reconstruct session content because it never held it.

2. Keys are derived locally from a secret embedded in the invite link. The relay
   never receives this secret; it only ever sees encrypted payloads.

3. Each session uses a one-time token. Nothing links one session to another, even
   from the same two devices.

Below the diagram, three feature items expand on these points briefly: key derivation
stays on device, SAS verification defeats man-in-the-middle attacks, sessions are
disposable by design.

**Action.** A single primary button: **Next: set up your server**.

**Design notes.** The language here is technical but plain. Avoid analogies that
require unpacking. A user who reads this screen should be able to explain to a
colleague why the SAS check matters — that is the measure of whether the content
is working.

---

## Screen 3 — Server configuration

**Purpose.** Collect the relay server address and validate it before proceeding.

This is the first of two configuration screens. It is labelled "Step 1 of 2" in the
eyebrow text.

**Content.**

A single input field: **Server address**. The placeholder shows the expected format
(`https://relay.example.org`). As soon as a valid URL is entered, Re:Link performs
a `GET /health` check against the server. The result is shown inline in the input
field:

- `● reachable` in green if the health check passes.
- `● unreachable` in amber if the server does not respond, with a hint to check the
  address and network connectivity.

The primary action button is disabled until the health check passes.

A collapsible or static panel below the input covers the case where the user does not
yet have a server running. It shows the minimum deployment command (`docker compose up -d`)
and links to the self-hosting documentation. This panel is not hidden behind a toggle —
first-time users should see it without having to look for it.

A warning note explains why using a third-party relay is inadvisable for high-stakes
connections: even a relay that cannot read session content can observe connection
metadata and client IP addresses.

**Action.** **Next: NAT traversal** — proceeds to screen 4. Disabled until health check
passes.

**Design notes.** The health check should run automatically on blur from the input
field, not require a separate "test connection" button. Immediate feedback reduces the
chance a user proceeds with a misconfigured server address.

---

## Screen 4 — ICE / NAT configuration

**Purpose.** Explain STUN and TURN, present the automatic default, and expose manual
overrides for advanced deployments.

This is the second of two configuration screens. It is labelled "Step 2 of 2".

**Content.**

A short explanation distinguishes STUN from TURN:

- STUN tells each device its public address so a direct connection can be attempted.
- TURN relays traffic when no direct path is possible. It is used only as a fallback.

A toggle — **Use server-derived ICE defaults** — is on by default. When on, Re:Link
pulls STUN and TURN configuration from the relay server automatically. The manual input
fields below the toggle are visible but dimmed and non-interactive while the toggle is
on.

If the user turns the toggle off, two fields become active:

- **Custom STUN server** — accepts a `stun:` URI.
- **Custom TURN server** — accepts a `turn:` URI, with separate fields for username
  and credential.

A hint below the manual fields states that custom ICE servers are for advanced
deployments and that most users should leave the toggle on.

**Action.** **Next: learn about verification** — proceeds to screen 5 regardless of
whether the toggle is on or off.

**Design notes.** The default-on toggle is important. The vast majority of users
should pass through this screen without touching anything. The manual fields exist
for operators running a separate coturn instance or using a third-party TURN provider;
they should not draw attention for users who do not need them.

---

## Screen 5 — SAS verification

**Purpose.** Establish the SAS verification habit before the user's first session.
This screen is not a configuration step — it is a security briefing.

**Content.**

The screen opens with a statement of what SAS verification is: every session generates
a 9-digit code derived deterministically from the shared secret. Both devices will show
the same code. Both users must read it and confirm it matches before the session opens.

A demonstration shows a static 9-digit code displayed as it will appear in the app,
with labels indicating that the same code appears on both the initiating and the
responding device.

A warning block states: if the codes do not match, the connection may be intercepted.
The correct response is to close the session immediately and establish contact via a
different channel.

Below the warning, three brief rules are listed:

- Read the code aloud over a voice call.
- Confirm it in person if possible.
- Never verify via the same channel used to share the invite link. If an attacker
  intercepted the link, they can intercept that channel too.

**Action.** **Understood — finish setup** — proceeds to screen 6.

**Design notes.** This is the most important screen in the flow. The content should
be short enough that a user under time pressure reads all of it. The warning about
not using the same channel for verification is the single most actionable piece of
security guidance Re:Link can give a first-time user; it needs to be stated plainly,
not buried.

The confirmation button copy ("Understood") signals that the user has acknowledged the
content, not just dismissed a screen. This is a minor but deliberate framing choice.

Once this screen is dismissed and onboarding completes, the flow will not be shown
again unless the app is reset via the `--reset` flag.

---

## Screen 6 — Ready

**Purpose.** Confirm that setup is complete and tell the user exactly what to do next.

**Content.**

A confirmation mark and a short heading: "You're ready."

Below it, a summary table shows what was configured:

| Field | Value |
|---|---|
| Relay server | `relay.example.org` |
| Server health | reachable |
| ICE servers | auto (from relay) |
| SAS verification | required |

All four rows should show green confirmation values. If the server health check has
since expired (e.g. the user spent a long time on earlier screens), a re-check runs
automatically when this screen is shown.

Below the summary, a brief first-connection instruction: tap **Create link** on the
main screen, share the link with your peer via any channel, and verify the SAS code
together before the session opens.

**Action.** **Open Re:Link** — dismisses the onboarding flow and navigates to the
main pairing screen. This completes the onboarding. The flow is not shown again on
subsequent launches unless the user explicitly re-runs it from settings.

---

## Navigation and progress

A segmented progress bar at the top of each screen shows six segments. Completed
screens fill solid; the current screen fills at reduced opacity; future screens remain
empty. The step counter ("2 / 6") appears below the bar.

Users can navigate to the previous screen using keyboard navigation (Escape or back
navigation) without resetting entered values. Navigating back from screen 3 to screen 2
does not clear the server address field.

The skip path from screen 1 to screen 3 marks screens 2 as complete in the progress
bar. The user can still navigate back to screen 2 from screen 3 if they want to read
the conceptual content.

---

## Onboarding persistence and reset

Once a user completes the onboarding flow, it is marked as completed and will not
appear again on subsequent app launches.

The `--reset` flag (available in start scripts) clears the onboarding completion state,
causing the flow to run again on the next app launch. This is useful for testing or
resetting the application to its initial state.

## Settings and configuration

After onboarding is complete, users can modify configuration settings by clicking the
settings button (gear icon) in the top right corner of the main screen. This opens a
settings popup modal with the following tabs:

- **Server** — modify the relay server address. Includes the same health check and
  validation as screen 3 of the onboarding flow.
- **Network** — adjust STUN and TURN configuration. Includes the toggle for automatic
  ICE defaults and manual field overrides from screen 4 of the onboarding flow.

Opening this settings modal does **not** re-launch the onboarding flow. It provides
quick access to modify these two settings without going through the full sequence again.

If the user wants to re-read the conceptual screens (How Re:Link works or SAS
verification), these can be accessed as optional reading material through a **Help**
entrypoint in the settings menu or main navigation.

---

## Error states

**Server unreachable.** The health check on screen 3 fails. The "Next" button remains
disabled. The input field shows `● unreachable` in amber. The hint text below the field
changes to: "Can't reach this server. Check the address and confirm the server is
running." The deployment panel remains visible.

**Health check timeout.** If the health check does not respond within 5 seconds, treat
as unreachable. Do not leave the user waiting with no feedback.

**Invalid URL format.** If the entered value is not a valid HTTPS URL, show a
validation error inline before attempting the health check: "Enter a full address
starting with https://".

**ICE credential missing.** If the user has turned off the automatic toggle on screen 4
and entered a TURN server address without credentials, the "Next" button is disabled
with a hint: "TURN credentials required — add a username and password."
