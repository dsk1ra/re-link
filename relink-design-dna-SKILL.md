---
name: relink-design-dna
description: >
  Re:Link's authoritative visual identity reference. Load this skill whenever working on any Re:Link
  UI, marketing, documentation, or design artefact — including Flutter screens, landing pages,
  README graphics, architecture diagrams, icons, onboarding flows, or pitch materials. Contains the
  canonical palette, type stack, spacing system, motion language, component rules, and aesthetic
  principles specific to Re:Link. Do not design anything Re:Link-related without consulting this first.
---

# Re:Link Design DNA

> **Status**: Canonical, v1.0 (June 2026). Decided through trend research + elicitation with Denys.
> Update tokens here first; never invent values in implementation that aren't recorded here.

---

## Core Idea

**Visible machinery, quiet confidence.**

Re:Link is a server-blind, ephemeral P2P tool. The UI shows its structure — borders, grids,
exposed protocol state — the way the protocol shows its guarantees. Nothing decorative, nothing
hidden. Trust is communicated by *surfacing* the cryptography legibly (key derivation, SAS
verification, what the server can and cannot see), not by hiding it behind a padlock icon.

**Register**: disciplined brutalism with an undercurrent of modern-SaaS reliability.
Raw, but potent — never "in your face". Think precision instrument, not hacker toy.

**Audience**: technically literate privacy-conscious users; developers evaluating the protocol;
academic reviewers.

---

## Palette

Dark-first. All greys are warm-tinted (~2–3% hue shift towards the orange accent) so the canvas
agrees with the accent rather than sitting under it inertly. Never pure neutral grey, never pure
black, never pure white.

### Foundations

| Token              | Hex       | Role                                                  |
|--------------------|-----------|-------------------------------------------------------|
| `--c-bg`           | `#201E1B` | Primary background (≈ #1E1E1E lightness, warm hue)    |
| `--c-surface`      | `#2A2723` | Cards, panels (+~6% luminance, same hue)              |
| `--c-surface-2`    | `#353129` | Raised elements: dialogs, popovers, hover surfaces    |
| `--c-border`       | `#2E2B26` | Subtle dividers, default card borders                 |
| `--c-border-strong`| `#423D35` | Emphasised borders, focused inputs, table frames      |
| `--c-text`         | `#ECE9E2` | Primary text (off-white — never `#FFFFFF`)            |
| `--c-text-muted`   | `#8C877C` | Secondary labels, captions (warm-tinted)              |
| `--c-text-faint`   | `#5E5A52` | Tertiary: timestamps, placeholders, disabled          |

### Brand accents (two, with strict roles)

| Token              | Hex       | Role                                                  |
|--------------------|-----------|-------------------------------------------------------|
| `--c-action`       | `#E06C2A` | Ember orange. CTAs, active nav, primary interactive   |
| `--c-action-dim`   | `#8F4516` | Pressed/hover-dim states of action elements           |
| `--c-info`         | `#5B84AD` | Desaturated slate blue. Links, selected-passive state, key fingerprints, technical metadata |
| `--c-info-dim`     | `#36506C` | Dim variant of info                                   |
| `--c-on-action`    | `#201E1B` | Text on orange fills                                  |

Rules: orange is the personality carrier; blue appears roughly 20% as often as orange and never
on a primary CTA. Their roles never blur. One colour used sparingly hits harder than five used
everywhere.

### Status semantics (traffic-light, desaturated for dark bg)

| Token              | Hex       | Role                                                  |
|--------------------|-----------|-------------------------------------------------------|
| `--c-ok`           | `#4CAF6E` | Connected / verified / E2EE established               |
| `--c-warn`         | `#D9A440` | Connecting / renegotiating / degraded                 |
| `--c-error`        | `#D95757` | Dropped / failed / destructive confirmation text      |

Rules: these three appear ONLY as status indicators — dots, badges, status text, countdowns.
NEVER on buttons, fills, surfaces, or decoration. This separation is what lets orange CTAs avoid
danger-association: semantics live exclusively in the triad.

---

## Typography

Two-font system: **mono is the voice, not the body.**

| Role            | Family                         | Notes                                          |
|-----------------|--------------------------------|------------------------------------------------|
| Identity / data | **Geist Mono**                 | Wordmark, eyebrows/section labels, session IDs, key fingerprints, status text, buttons, code |
| Body / UI       | **Space Grotesk**              | Body copy, headings, inputs, paragraphs        |
| Display option  | Departure Mono                 | Optional pixel-flavoured display for wordmark/hero only — never body or data |
| Upgrade path    | Berkeley Mono (paid)           | Drop-in replacement for Geist Mono if budget allows |

Recurring structural motif: **uppercase mono eyebrows with wide tracking** (`letter-spacing:
0.08–0.14em`, 10–12px, `--c-text-muted`) labelling every major section/card.

### Type scale

| Name        | Size | Family        | Weight | Tracking | Use                          |
|-------------|------|---------------|--------|----------|------------------------------|
| display     | 40px | Space Grotesk | 600    | -0.02em  | Hero/landing only            |
| h1          | 28px | Space Grotesk | 600    | -0.01em  | Screen titles                |
| h2          | 20px | Space Grotesk | 500    | 0        | Section headings             |
| body        | 15px | Space Grotesk | 400    | 0        | Paragraphs, descriptions     |
| label       | 13px | Geist Mono    | 500    | 0.02em   | Buttons, nav, form labels    |
| eyebrow     | 11px | Geist Mono    | 700    | 0.10em   | UPPERCASE section labels     |
| data        | 14px | Geist Mono    | 400    | 0.02em   | IDs, fingerprints, hashes    |
| caption     | 11px | Geist Mono    | 400    | 0.04em   | Timestamps, status, meta     |

Flutter: load via google_fonts (`GoogleFonts.spaceGrotesk`, `GoogleFonts.geistMono`); map onto
TextTheme (displayLarge→display, titleLarge→h1, titleMedium→h2, bodyMedium→body,
labelMedium→label, labelSmall→eyebrow/caption).

---

## Shape & Borders

Disciplined brutalism: structure is expressed through borders and luminance, never shadows.

| Token           | Value | Applied to                                  |
|-----------------|-------|---------------------------------------------|
| `--radius-sm`   | 2px   | Buttons, chips, inputs, badges              |
| `--radius-md`   | 4px   | Cards, panels, dialogs                      |
| `--radius-none` | 0px   | Tables, code blocks, full-bleed sections    |

- 1px solid borders (`--c-border`, `--c-border-strong` on focus/emphasis) are the primary depth
  mechanism. Every card and panel is bordered.
- NO drop shadows. Elevation = surface luminance step (`bg → surface → surface-2`).
- NO pill shapes, NO radius above 4px anywhere. NO gradients on surfaces.
- Flat fills only. Hard edges are a feature.

---

## Spacing & Layout

4px base unit. Brutalist density needs generous air to read as deliberate, not careless:
take the spacing that feels like enough, then increase it.

| Token     | Value | Use                              |
|-----------|-------|----------------------------------|
| `--sp-1`  | 4px   | Icon–label gaps                  |
| `--sp-2`  | 8px   | Tight internal padding           |
| `--sp-3`  | 16px  | Component internal padding       |
| `--sp-4`  | 24px  | Card padding, gaps between cards |
| `--sp-5`  | 40px  | Section gaps                     |
| `--sp-6`  | 64px  | Screen-level / hero breathing    |

Layout: visible grid logic; hairline rules and bordered regions over floating cards. Max content
width 1100px on marketing surfaces. Structured density over hidden complexity — every data point
earns its place by the action it enables.

---

## Motion

Subtle and functional everywhere, with ONE expressive exception.

- Durations: 120ms (micro: hover, press), 200ms (standard: panels, fades), 320ms (large: sheets).
- Easing: `cubic-bezier(0.2, 0, 0, 1)` (decelerate). No bounce, no spring, no overshoot.
- **The signature exception — the handshake.** Session establishment gets a choreographed
  animation: two nodes converging, key-derivation steps ticking through (k_sig → k_mac → SAS),
  status dot transitioning amber → green. Restraint everywhere else is what makes this one
  moment land. Budget ~1.2s, skippable, never blocks interaction.
- Ephemeral expiry/countdowns may pulse gently in `--c-warn` as they approach zero.

---

## Iconography

Outlined, 1.5px stroke, geometric, 20px grid (Lucide or Tabler — pick one, never mix).
No filled icons except status dots. Status dots are 7–8px circles in the semantic triad.

---

## Signature Element

**The animated handshake + exposed protocol state.** Re:Link's trust argument rendered visually:
the UI confesses its machinery. Connection screens show what the server sees (almost nothing)
versus what the peers share, key fingerprints are first-class UI in `data` style, and SAS
verification is a designed moment, not a buried dialog.

---

## What to Avoid

- Corporate/sterile SaaS polish: big rounded containers, soft shadows, pastel gradients.
- Pure neutral greys (#1E1E1E exactly = unthemed Electron look) and pure black/white.
- The cartoon neo-brutalist strain (thick black borders + offset shadows, Gumroad-style).
- Neon-green terminal/hacker clichés.
- Traffic-light colours anywhere except status indicators.
- Blue and orange swapping roles, or either appearing as large decorative fills.
- More than one expressive animation. Bounce/spring easing.
- Padlock-icon trust theatre — show the actual mechanism instead.

---

## How to Apply This Skill

1. Load this file at the start of any Re:Link design task.
2. Derive every colour, type, spacing and rounding decision from the tokens above.
3. If a decision isn't covered, follow the philosophy ("visible machinery, quiet confidence";
   disciplined brutalism; semantic colour separation), then record the new token here.
4. Cross-reference /mnt/skills/public/frontend-design/SKILL.md for execution process.
