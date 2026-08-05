---
name: SQL Cheat Sheet
description: A warm-editorial ledger for an honest, interview-prep SQL learning resource.
colors:
  accent-terracotta: "#b8532a"
  ink: "#1a1917"
  paper: "#fbfaf9"
  surface: "#ffffff"
  muted: "#6b6862"
  hairline: "#e5e1db"
  key-gold: "#c8952a"
  relation-green: "#4a9d6e"
  unique-violet: "#7a5cc4"
  syntax-comment: "#3f7d3a"
  syntax-function: "#7a4bb8"
  syntax-string: "#8a6a1f"
  syntax-number: "#2f6f8f"
typography:
  display:
    fontFamily: "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "clamp(1.6rem, 3vw, 2.15rem)"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.02em"
  stat:
    fontFamily: "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "1.45rem"
    fontWeight: 650
    letterSpacing: "-0.02em"
    fontFeature: "'tnum'"
  headline:
    fontFamily: "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "1.4rem"
    fontWeight: 700
    letterSpacing: "-0.01em"
  body:
    fontFamily: "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.6
  small:
    fontFamily: "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "0.9rem"
    fontWeight: 400
  label:
    fontFamily: "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
    fontSize: "0.8rem"
    fontWeight: 600
    letterSpacing: "0.1em"
  data:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "0.72rem"
    lineHeight: 1.55
  meta:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "0.66rem"
  badge:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "0.58rem"
    fontWeight: 700
    letterSpacing: "0.04em"
rounded:
  xs: "4px"
  sm: "7px"
  md: "8px"
  lg: "10px"
  xl: "11px"
  pill: "999px"
  circle: "50%"
spacing:
  xs: "0.35rem"
  sm: "0.7rem"
  md: "1rem"
  lg: "1.75rem"
  xl: "4rem"
components:
  tab:
    backgroundColor: "transparent"
    textColor: "{colors.muted}"
    rounded: "{rounded.md}"
    padding: "0.5rem 0.75rem"
  tab-selected:
    backgroundColor: "{colors.accent-terracotta}"
    textColor: "#ffffff"
    rounded: "{rounded.md}"
    padding: "0.5rem 0.75rem"
  toolbar-button:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    rounded: "{rounded.sm}"
    padding: "0.32rem 0.7rem"
  question-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "0.8rem 0.9rem 0.85rem"
  skill-chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    rounded: "{rounded.pill}"
    padding: "0.15rem 0.55rem"
  panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "0.65rem 1rem"
  schema-badge-pk:
    backgroundColor: "{colors.key-gold}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xs}"
    padding: "0.08rem 0.3rem"
  schema-badge-fk:
    backgroundColor: "{colors.relation-green}"
    textColor: "#0d1f16"
    rounded: "{rounded.xs}"
    padding: "0.08rem 0.3rem"
  schema-badge-uq:
    backgroundColor: "{colors.unique-violet}"
    textColor: "#ffffff"
    rounded: "{rounded.xs}"
    padding: "0.08rem 0.3rem"
---

# Design System: SQL Cheat Sheet

## Overview

**Creative North Star: "The Ledger"**

The system is an accounts ledger rendered with the warmth of an editorial page. A ledger's job is to reconcile: every value is accounted for, every column lines up, and nothing is fabricated — which is exactly the product's promise (queries written against what the data actually contains, 113/113 verified, caveats named rather than hidden). The visual world makes that rigor legible. Monospace carries anything that is *data* — schema fields, SQL, result rows, file paths, timings — so the reader can trust that what they see is the literal record. Proportional sans carries the *reading* — the business questions, the teaching prose, the labels — so the page stays a document you want to stay inside, not a console you endure.

Warmth keeps the rigor from turning clinical. The ground is a warm off-white paper (#fbfaf9), not a cold grey; ink is a near-black brown-black (#1a1917), not pure #000; the one accent is a terracotta (#b8532a) that reads like a proofreader's red pencil more than a UI primary. Surfaces are flat and quiet at rest, separated by hairlines, and lift only when you touch them. The result should feel authored and exacting — a printed statement you could hand to a reviewer — while remaining a comfortable long-form read across five projects and 113 questions.

The world rejects the two failure modes of its category: the cold, high-chrome "developer dashboard" (neon-on-charcoal, heavy gradients, glowing cards) and the flat generic "docs template." Neither would carry the honesty argument. This is paper and pencil precision, not a control panel.

**Key Characteristics:**
- Warm paper ground, brown-black ink, a single terracotta accent used sparingly.
- Monospace for anything that is data; proportional sans for anything that is reading.
- Flat by default; a soft ambient shadow and a 2px rise appear only on interaction.
- Hairline borders and generous radii do the separating; color is reserved for meaning.
- Fluid and intrinsic — the layout reflows by content weight, with no width breakpoints.

## Colors

A warm, low-saturation palette where color is spent almost entirely on *meaning* — structural roles in the schema and difficulty in the levels — never on decoration.

### Primary
- **Terracotta Pencil** (#b8532a): the single brand accent and the one voice of emphasis. Carries Q-numbers, section headings inside result panels, active tab fill, links, the numbered project medallion, focus rings, and the `selection` highlight. In the SQL highlighter it doubles as the keyword color. Dark scheme: warmer clay #e08155.

### Secondary — Structural (schema semantics)
These three hues encode relational roles in the schema map and nowhere decorative.
- **Key Gold** (#c8952a): PRIMARY KEY columns — badge fill and column tint. Dark: #d8a657.
- **Relation Green** (#4a9d6e): FOREIGN KEY columns and their `→ table.col` reference line. Dark: #6ec49a.
- **Unique Violet** (#7a5cc4): UNIQUE-INDEX columns. Dark: #a78bfa.

### Tertiary — Syntax (SQL highlighting)
A muted, print-like code palette. Keywords reuse the Terracotta Pencil; the rest are quiet earth tones so code reads as prose, not neon.
- **Comment Green** (#3f7d3a) · **Function Violet** (#7a4bb8) · **String Olive** (#8a6a1f) · **Number Teal** (#2f6f8f). Each has a lighter dark-scheme counterpart (see the sidecar).

### Neutral
- **Warm Paper** (#fbfaf9): the page ground. Dark: near-black warm #161513.
- **Brown-Black Ink** (#1a1917): primary text. Dark: #eceae6.
- **Muted Stone** (#6b6862): secondary text — ledes, captions, metadata, table cell values. Dark: #9a958c.
- **Hairline** (#e5e1db): every border and divider; the ledger's rules. Dark: #2c2a27.
- **Card Surface** (#ffffff): cards, panels, tabs, sticky chrome — one step brighter than the paper. Dark: #1e1d1a.

### Named Rules
**The One Pencil Rule.** There is exactly one brand accent (Terracotta Pencil) and it stays rare — Q-numbers, active state, links, focus. If a screen looks terracotta-heavy, it's wrong; the accent earns attention by scarcity.

**The Color-Is-Meaning Rule.** A hue only appears when it encodes something true — a key role, a difficulty level, a syntax token. No color is used to decorate a surface. Neutrals and hairlines do all the structural work.

## Typography

**Display / Body Font:** the native system sans stack (`ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`) — zero webfont weight, instantly legible, neutral enough to let the data lead.
**Data / Mono Font:** the native monospace stack (`ui-monospace, SFMono-Regular, Menlo, monospace`).

**Character:** the pairing is the whole thesis — proportional sans is the *narrator*, monospace is the *record*. The moment text is something the database literally produced, it becomes mono; the moment it's something a human wrote to explain, it's sans.

### Hierarchy
Every size is one of a closed **8-step scale** (the `--fs-*` tokens); nothing is sized ad hoc. The steps keep real gaps (0.9 / 0.8 / 0.72 / 0.66 / 0.58rem) so each tier stays distinguishable.
- **Display** (`--fs-display`, 700, `clamp(1.6rem, 3vw, 2.15rem)`, lh 1.15, ls −0.02em): the page title only.
- **Stat** (`--fs-stat`, 650, 1.45rem, ls −0.02em, tabular figures): the header metric numbers. Signature — big, tight, tabular.
- **Headline** (`--fs-title`, 700, 1.4rem, ls −0.01em): project titles (h2).
- **Body** (400, 1rem/1.6): the reading base.
- **Small** (`--fs-md`, 0.9rem): small body and controls — the lede, question-card text (lh 1.5), tabs, project metadata, panel summaries, footer.
- **Label** (`--fs-sm`, 0.8rem, 600, ls 0.1em, UPPERCASE for level names): level headings, result-panel headings, stat captions, toolbar buttons, counts, hints.
- **Data** (`--fs-xs`, 0.72rem, mono, lh 1.55): schema field names, SQL, result tables, skill chips, and the Q-number tag.
- **Meta** (`--fs-2xs`, 0.66rem, mono): fine print — column types, FK reference lines, file paths, timings, the schema legend.
- **Badge** (`--fs-3xs`, 0.58rem, 700, ls 0.04em, mono): the PK / FK / UQ role badges.

### Named Rules
**The Record-Is-Mono Rule.** If a value came out of the database — a column name, a SQL token, a result cell, a row count, a millisecond timing — it is set in monospace. If a human wrote it to teach, it is set in sans. Never blur the two.

**The Closed-Scale Rule.** Every font-size is one of the eight `--fs-*` steps. When a new size feels necessary, reuse the nearest step or add a documented one — never a fresh literal. Below `body`, size differences must stay large enough to read as a change of tier, not a wobble.

## Layout

A single centered column (`.wrap`) with fluid side padding (`clamp(1rem, 3vw, 2.25rem)`) and generous top/bottom rhythm (1.75rem / 4rem). The system is **intrinsically responsive with no width breakpoints** — every arrangement is achieved with `flex-wrap`, `clamp()`, and `min(…, 100%)` guards rather than `@media (max-width)`. The only media queries are `prefers-color-scheme`, `prefers-reduced-motion`, and `print`.

- **Header** is a two-part `flex` that wraps: the intro (title + lede, lede capped at 66ch) beside a right-aligned block of tabular stat numbers.
- **Navigation** is a pill tab-bar (one rounded surface holding the five project tabs) that wraps its tabs on narrow widths.
- **Question grid** changes density by *word budget*, not viewport: Beginner questions are terse so they run six-up (`cols6`), and each higher level drops the column count as questions get longer (`cols4` → `cols3` → `cols2`), so line length stays readable. Cards have a `min-width` floor and wrap.
- **Schema cards** flow in a wrap; a wide table splits its own field list into 2 or 3 internal columns (`split2` / `split3`, triggered at >10 / >20 fields) so a card grows sideways, not tall. `min(…, 100%)` keeps it from overflowing a narrow screen.
- **SQL + result** sit side by side in a `flex` that wraps to stacked on narrow widths; each has `min-width: 0` so neither forces page-level horizontal scroll. Wide result tables and long SQL scroll *inside their own containers*.

**The Contained-Scroll Rule.** Overflow is always solved inside a bordered box (`.tblwrap`, `pre.sql`) — the page body itself never scrolls sideways.

The reading column is capped at **100rem** (`.wrap { max-width:100rem }`, centered): wide enough for the widest intended layout (the 6-up beginner grid, ~95rem) yet narrow enough that ultra-wide monitors stop over-stretching the grid and schema tables. Consecutive query blocks stacked in one panel are divided by a hairline **ledger rule** (`.rq + .rq { border-top:1px solid var(--line) }`), so each SQL-and-result record reads as its own line item rather than one continuous wall.

## Elevation & Depth

**Flat by default; a soft lift on interaction.** Surfaces rest flat on the paper, distinguished by a one-step-brighter fill (#fff on #fbfaf9) and a hairline border. Depth is not ambient — it is a *response*. A question card sits flat until hover, when it rises 2px (`translateY(-2px)`) and its border warms to terracotta. The one persistent shadow is deliberately near-invisible, present only to keep white cards from dissolving into near-white paper.

### Shadow Vocabulary
- **Paper Lift** (`box-shadow: 0 1px 2px rgba(0,0,0,.05), 0 4px 12px rgba(0,0,0,.04)`): the single soft shadow token, on cards, the tab-bar, and result-table headers. In dark scheme it deepens to `0 1px 2px rgba(0,0,0,.3), 0 4px 12px rgba(0,0,0,.25)`.

### Named Rules
**The Flat-By-Default Rule.** Surfaces are flat and hairline-bordered at rest. Motion and shadow are earned by interaction (hover, focus, the target flash) — never applied as baseline decoration.

## Shapes

Gently rounded rectangles on a hairline grid, with two deliberate geometric exceptions.
- **Radius ladder:** inline badges/code chips 4px → buttons, code blocks, and table frames 7px → tabs 8px → cards and panels 10px → the tab-bar shell 11px. Corners soften as the surface grows.
- **Pills:** skill chips are fully rounded (999px) — the one soft, tag-like silhouette.
- **Circles:** the numbered project medallion and the per-tab count discs are perfect circles (50%) — the ledger's line-item numbers.
- **Borders:** a single 1px hairline (`--line`) does nearly all separation. The one heavier stroke is the 2px ink underline beneath each project header, like a ruled total.

## Components

### Buttons
- **Toolbar buttons** ("Expand all / Collapse all"): quiet by design — surface fill, hairline border, muted text, 7px radius, compact `0.32rem 0.7rem` padding. **Hover:** text and border shift to terracotta (color only; no fill change).
- **Tabs (primary navigation):** see Navigation.

### Chips
- **Skill chips:** fully-rounded (999px) hairline pills on the card surface with muted text (0.72rem). Read-only labels, not interactive filters. They tag each difficulty level with the SQL techniques it drills.

### Cards / Containers
- **Question card:** the workhorse. Card surface, hairline border, 10px radius, Paper Lift shadow, `0.8rem 0.9rem 0.85rem` padding, column layout (Q-number → question → footer with row count + timing + "view SQL →"). **Hover:** rises 2px, border warms to terracotta, the "view SQL →" affordance goes to full opacity.
- **Schema table card:** a mono-titled sub-card (table name + row/column count; a styled non-heading title, so the schema panel doesn't inject `h5`s into the document outline between the project `h2` and the level `h3`s) over a list of columns; derived tables are full-strength, untouched source (`raw_*`) tables are faded to 0.72 opacity — the ledger showing original vs. reconciled.

### Disclosure Panels
- **`<details>` panel:** the standard container for schema and for SQL/results. Hairline-bordered, 10px radius, card surface. Summary is a 0.84rem semibold row with a terracotta triangle (▸) that rotates 90° on open. Print styles force every panel open.

### Navigation (Tabs)
- **Style:** a single rounded (11px) tab-bar surface with hairline border and Paper Lift shadow, holding five tabs. Each tab pairs a circular number disc + short name + count.
- **States:** default is muted text on transparent; **hover** fills with the paper tone; **selected** fills terracotta with white text and an inverted (translucent-white) number disc.
- **Behavior:** a proper ARIA tablist — roving `tabindex`, Arrow/Home/End keys, `aria-selected`, and hidden inactive panels. Focus shows a 2px terracotta outline with 3px offset.

### Signature Components
- **The Schema Map:** the defining component. Per project, a disclosure that lays out every table as a card with PK/Gold, FK/Green, UQ/Violet column badges, FK reference lines (`→ table.col`), row/column counts, and raw-vs-derived fading. This is the ledger's chart of accounts.
- **The SQL Reader:** a hand-tokenized `pre.sql` code block in the muted syntax palette, with the leading `-- Qn:` comment highlighted in terracotta, shown beside its **result table** (mono, `nowrap`, contained horizontal scroll, hover row highlight) and a deep-link to the exact line on GitHub. Clicking a question card opens the relevant panel, smooth-scrolls to it, and plays a brief terracotta background flash to orient the reader.

## Do's and Don'ts

### Do:
- **Do** keep the accent rare — Terracotta Pencil for Q-numbers, active state, links, and focus only (**The One Pencil Rule**).
- **Do** set every database-produced value (columns, SQL, result cells, counts, timings) in monospace, and every human explanation in sans (**The Record-Is-Mono Rule**).
- **Do** keep surfaces flat with hairline borders at rest; reserve the Paper Lift shadow and the 2px rise for interaction (**The Flat-By-Default Rule**).
- **Do** solve overflow inside bordered scroll boxes so the page never scrolls sideways (**The Contained-Scroll Rule**).
- **Do** let content weight drive density — more words, fewer columns.
- **Do** provide full dark-scheme counterparts for every token; the warm-paper character must survive into dark (warm near-black, not cold charcoal).

### Don't:
- **Don't** spend color on decoration — a hue must encode a key role, a difficulty level, or a syntax token (**The Color-Is-Meaning Rule**).
- **Don't** rely on hue alone to tell difficulty from schema role: the level colors (green/gold/terracotta/violet) currently reuse the badge hues (FK/PK/accent/UQ), so always pair level color with its dot + uppercase label. *(A future `colorize` pass may separate the two ramps.)*
- **Don't** introduce webfonts, gradients, gl, neon-on-charcoal "dashboard" styling, or heavy drop shadows — they break the paper-and-pencil world.
- **Don't** mute text with `opacity` (it drops small text under contrast minimums); reach for the Muted Stone token instead.
- **Don't** bake content into markup — the surface is a thin shell rendered from data; keep it that way.
