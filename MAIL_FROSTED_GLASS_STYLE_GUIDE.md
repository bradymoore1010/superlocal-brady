# Mail Frosted Glass Interface Style Guide

## Purpose

This guide translates the attached visual reference into a reproducible design system for **Mail**, the minimal, keyboard-first Gmail client. It is intended to be precise enough for a designer or frontend engineer to recreate the interface consistently without needing to reinterpret the source image.

The product structure does not change. Mail remains an email-only desktop application with:

- a compact mailbox sidebar;
- an inbox message list or focused conversation reader;
- a persistent inline reply composer;
- fast keyboard navigation and a command menu;
- compact compose, archive, search, more, formatting, attachment, and send controls;
- no calendar, tasks, mobile framing, dashboard modules, or card-grid homepage.

This is a visual reskin and interaction mockup, not a product-scope redesign.

## Reference interpretation

### What is retained

- The central window's translucent, frosted material.
- The aqua-to-mint-to-warm-ivory ambient color transmission.
- The visible layering of glass on glass.
- Large continuous corner radii.
- Soft inner highlights and broad, diffuse outer shadows.
- Near-black SF-style typography with compact line height.
- Rounded rectangular buttons and dropdowns with quiet borders.
- Native macOS traffic-light controls.
- Calm spacing, simple hierarchy, and very limited visible chrome.

### What is explicitly excluded

- The centered dock and all application icons.
- The orange identity color.
- The white rounded-square identity tile beside the title.
- The word “Personal,” “Edit Dock,” and dock-management semantics.
- Decorative modules unrelated to email.
- Heavy white cards, opaque gray dashboard panels, saturated gradients, or neon glass.
- Generic web-app browser chrome, mobile UI conventions, calendar, and task features.

### Evidence boundary

The source is a flattened JPEG measuring **2028 × 1062 px**. Geometry and displayed colors can be measured from the raster. True material opacity, blur radius, font file, and the unblurred wallpaper behind the glass cannot be recovered exactly; the implementation values below are calibrated recommendations intended to reproduce the visible result.

The reference appears to be captured at approximately **2× macOS Retina scale**. Both source pixels and suggested 1× logical values are included where useful.

## Reference geometry

| Element | Approximate source bounds | Approximate 1× logical size | Notes |
| --- | ---: | ---: | --- |
| Frosted outer window | x 184–1829, y 249–835 | 823 × 293 pt | Main translucent shell |
| Outer corner radius | 42–46 px | 21–23 pt | Continuous macOS-style curve |
| Traffic-light centers | x 238, 284, 330; y 304 | 23 pt center spacing | 14–15 px source radius |
| Top/right inset | 39–42 px | 20–21 pt | Consistent control margin |
| Account dropdown | x 1537–1788, y 276–347 | 126 × 36 pt | Raised pale glass |
| Secondary dropdown | x 1592–1788, y 376–443 | 98 × 34 pt | Slightly shorter than account control |
| Title baseline region | x 323–506, y 377–412 | about 92 × 18 pt | Bold display text |
| Subtitle baseline region | x 325–557, y 427–449 | about 116 × 11 pt | Medium, low-contrast metadata |
| Bright inner glass field | x 225–1788, y 490–802 | 782 × 156 pt | Structural glass layer |
| Inner field corner radius | 40–44 px | 20–22 pt | Nearly matches outer radius |
| Darker nested glass strip | x 294–1717, y 568–725 | 712 × 79 pt | Material reference only; dock content is excluded |
| Nested strip radius | 37–42 px | 19–21 pt | Used as the model for selected/raised surfaces |

The source uses an unusually coherent radius family: the outer shell and large nested surfaces are all around 20–23 logical points, while controls are around 12–14 points. Mail should preserve this two-tier radius system.

## Design character

Mail should feel like a real, quiet macOS utility seen through softly tinted architectural glass. The interface is tactile but not glossy, playful, or toy-like. Frosting obscures the backdrop enough that every label remains immediately legible. Color comes from light passing through the window, not from colorful UI components.

The visual priorities are:

1. Text and email content.
2. Current selection and keyboard focus.
3. Navigation and actions.
4. Ambient glass and desktop context.

The glass is always subordinate to reading and speed.

## Layer model

Every surface belongs to one of five depth levels. Do not invent additional elevations.

### Depth 0 — desktop ambience

Purpose: make transparency visible without becoming product content.

- Base colors: deep emerald, blue-green, moss, and restrained ochre.
- Suggested anchors: `#073F38`, `#0C6357`, `#177B6C`, `#A79857`, `#D0C486`.
- Texture should be broad and organic, with no recognizable photo subject.
- Keep the brightest region behind the upper-middle of the Mail window so the ivory transmission is visible.
- Avoid sharp detail directly behind body copy.
- If a static mockup needs a deterministic background, use one abstract low-frequency texture and lock its crop at 1440 × 900.
- If no desktop backdrop is available, use the fallback ambient field defined in the token block below.

### Depth 1 — application window glass

Purpose: define the Mail window as one continuous translucent object.

- Background: cool mint glass with a warm ivory light bloom through the upper center.
- Target background recipe: `rgba(213, 236, 224, 0.58)` over the ambient field.
- Backdrop blur: **42 px**.
- Backdrop saturation: **115%**.
- Local surface saturation: **92%** so the result stays milky rather than vivid.
- Border: `1px solid rgba(244, 255, 249, 0.38)`.
- Inner highlight: `inset 0 1px 0 rgba(255, 255, 255, 0.32)`.
- Outer shadow: `0 28px 72px rgba(4, 37, 32, 0.28)`.
- Secondary grounding shadow: `0 6px 20px rgba(4, 37, 32, 0.12)`.
- Desktop radius: **28 px** in the 1440 × 900 prototype; use **22 px** at the reference's approximately 823 pt window width.
- Clip all descendants to the continuous outer curve.

### Depth 2 — structural glass

Purpose: separate sidebar, inbox, reader, and major content regions without opaque walls.

- Default fill: `rgba(211, 247, 239, 0.30)`.
- Bright variant: `rgba(225, 255, 248, 0.38)`.
- Backdrop blur: **28 px**.
- Border: `1px solid rgba(245, 255, 252, 0.22)`.
- Inner highlight: `inset 0 1px 0 rgba(255, 255, 255, 0.24)`.
- Radius: **20 px** for large grouped regions.
- Structural surfaces may touch window edges only when the outer window performs the clipping.
- Use spacing and subtle luminosity changes before adding divider lines.

### Depth 3 — nested glass

Purpose: selected rows, conversation cards, reply composer, command menu, popovers, and focused groupings.

- Neutral fill: `rgba(173, 205, 196, 0.36)`.
- Light fill: `rgba(239, 250, 246, 0.58)`.
- Selected fill: `rgba(143, 184, 173, 0.44)`.
- Backdrop blur: **18 px**.
- Border: `1px solid rgba(15, 58, 50, 0.12)`.
- Top highlight: `inset 0 1px 0 rgba(255, 255, 255, 0.30)`.
- Shadow for floating variants only: `0 12px 34px rgba(4, 37, 32, 0.16)`.
- Radius: **14–18 px**, depending on size.
- Do not wrap every row in this material. Use it only for selection, grouped messages, the persistent composer, and temporary overlays.

### Depth 4 — raised controls

Purpose: buttons, dropdowns, search, segmented controls, and keyboard hints.

- Fill: `rgba(246, 252, 248, 0.72)`.
- Hover fill: `rgba(255, 255, 255, 0.80)`.
- Pressed fill: `rgba(211, 229, 222, 0.72)`.
- Border: `1px solid rgba(255, 255, 255, 0.42)` plus a dark optical edge via `box-shadow: 0 0 0 0.5px rgba(16, 49, 42, 0.10)`.
- Backdrop blur: **14 px**.
- Height: **32 px** standard, **36 px** prominent.
- Radius: **11 px** standard, **13 px** prominent.
- Horizontal padding: **12 px** standard, **14 px** prominent.
- Gap between label and icon or key hint: **8 px**.
- Shadow: `0 2px 8px rgba(4, 37, 32, 0.07)`.

### Depth 5 — modal focus

Purpose: command palette and compose overlay.

- Window scrim: `rgba(3, 25, 21, 0.18)` with `backdrop-filter: blur(3px)`.
- Modal fill: `rgba(232, 245, 239, 0.78)`.
- Backdrop blur: **36 px**.
- Border: `1px solid rgba(255, 255, 255, 0.44)`.
- Radius: **18 px**.
- Shadow: `0 30px 80px rgba(1, 24, 20, 0.30)`.
- The overlay must remain compact; it is not a full-page dialog.

## Sampled color targets

These are representative flattened colors sampled from low-detail parts of the JPEG. They are visual targets, not opaque UI tokens.

| Region | Approximate displayed RGB | Hex target |
| --- | ---: | ---: |
| Outer glass, cool left | 141, 190, 172 | `#8DBEAC` |
| Outer glass, aqua-green | 149, 199, 170 | `#95C7AA` |
| Outer glass, warm center | 213, 219, 180 | `#D5DBB4` |
| Outer glass, warm mint right | 203, 219, 179 | `#CBDBB3` |
| Bright structural glass, left | 164, 218, 212 | `#A4DAD4` |
| Bright structural glass, center | 187, 227, 209 | `#BBE3D1` |
| Nested smoky glass, open area | roughly 155, 196, 180 | `#9BC4B4` |
| Dark backdrop green | roughly 19, 75, 64 | `#134B40` |

Do not apply these hex values as solid fills. The correct appearance comes from translucent fill, background blur, a slight border, and the ambient field underneath.

## Core color tokens

### Text

- `--ink-primary: #111713` — titles, unread senders, primary labels.
- `--ink-secondary: rgba(17, 23, 19, 0.68)` — preview text, secondary actions.
- `--ink-muted: rgba(17, 23, 19, 0.50)` — timestamps and metadata.
- `--ink-faint: rgba(17, 23, 19, 0.36)` — placeholders and disabled labels.
- `--ink-on-dark: rgba(248, 252, 249, 0.96)` — primary dark button text.

The reference uses near-black text rather than pure black. Preserve the faint green undertone so type belongs to the glass environment.

### Lines and optical edges

- `--line-light: rgba(255, 255, 255, 0.32)`.
- `--line-neutral: rgba(18, 55, 47, 0.11)`.
- `--line-strong: rgba(18, 55, 47, 0.17)`.
- `--focus-ring: rgba(17, 79, 67, 0.62)`.

### Semantic accents

The visual reference does not justify an orange product accent. Mail should use almost no accent color.

- Unread indicator: `#15201B`.
- Selected/focus tint: `rgba(117, 166, 153, 0.30)`.
- Success: `#1F7A50`, used only for status.
- Destructive: `#A13C32`, used only inside destructive confirmation states.
- Link: `#165F59`, underlined on hover.

## CSS token baseline

```css
:root {
  color-scheme: light;

  --font-ui: "SF Pro Text", "SF Pro Display", -apple-system,
    BlinkMacSystemFont, "Helvetica Neue", sans-serif;

  --ink-primary: #111713;
  --ink-secondary: rgba(17, 23, 19, 0.68);
  --ink-muted: rgba(17, 23, 19, 0.50);
  --ink-faint: rgba(17, 23, 19, 0.36);
  --ink-on-dark: rgba(248, 252, 249, 0.96);

  --glass-window: rgba(213, 236, 224, 0.58);
  --glass-structure: rgba(211, 247, 239, 0.30);
  --glass-structure-bright: rgba(225, 255, 248, 0.38);
  --glass-nested: rgba(173, 205, 196, 0.36);
  --glass-nested-light: rgba(239, 250, 246, 0.58);
  --glass-selected: rgba(143, 184, 173, 0.44);
  --glass-control: rgba(246, 252, 248, 0.72);
  --glass-control-hover: rgba(255, 255, 255, 0.80);
  --glass-control-pressed: rgba(211, 229, 222, 0.72);

  --line-light: rgba(255, 255, 255, 0.32);
  --line-neutral: rgba(18, 55, 47, 0.11);
  --line-strong: rgba(18, 55, 47, 0.17);

  --blur-window: 42px;
  --blur-structure: 28px;
  --blur-nested: 18px;
  --blur-control: 14px;

  --radius-window: 28px;
  --radius-region: 20px;
  --radius-card: 16px;
  --radius-control: 11px;
  --radius-small: 7px;

  --shadow-window: 0 28px 72px rgba(4, 37, 32, 0.28),
    0 6px 20px rgba(4, 37, 32, 0.12);
  --shadow-float: 0 12px 34px rgba(4, 37, 32, 0.16);
  --shadow-control: 0 2px 8px rgba(4, 37, 32, 0.07);

  --ease-snappy: cubic-bezier(0.2, 0.8, 0.2, 1);
  --duration-fast: 90ms;
  --duration-standard: 140ms;
}
```

Recommended ambient fallback:

```css
.desktop {
  background-color: #0b554a;
  background-image:
    radial-gradient(80% 120% at 56% 8%, rgba(218, 202, 126, 0.74), transparent 46%),
    radial-gradient(90% 90% at 10% 70%, rgba(12, 91, 79, 0.92), transparent 62%),
    radial-gradient(80% 100% at 95% 80%, rgba(3, 53, 48, 0.96), transparent 58%);
}
```

This is the one approved use of broad gradients: a low-detail desktop ambience behind the product. Product controls and content surfaces do not use decorative gradients.

## Material implementation recipe

Use a real backdrop filter whenever the renderer supports it:

```css
.glass {
  position: relative;
  background: var(--glass-window);
  border: 1px solid var(--line-light);
  box-shadow: var(--shadow-window), inset 0 1px 0 rgba(255, 255, 255, 0.32);
  backdrop-filter: blur(var(--blur-window)) saturate(115%);
  -webkit-backdrop-filter: blur(var(--blur-window)) saturate(115%);
}
```

Rules:

- The backdrop must contain visible tonal variation or the surface will look like flat translucent green.
- Never stack more than three active `backdrop-filter` elements over the same pixel area. Too many filters become muddy and expensive.
- Nested glass should reduce blur as depth increases: 42 → 28 → 18 → 14 px.
- Increasing elevation makes a surface lighter and slightly less transparent, not more colorful.
- Preserve a 1 px highlight on upper edges; omit shiny multi-stop borders.
- Keep shadows cool and green-black. Neutral black shadows make the shell look pasted on.
- If `backdrop-filter` is unavailable, use the sampled flattened color targets and add 2–3% monochromatic noise. Do not leave a transparent fallback that harms contrast.

## Typography

### Family

The screenshot is visually consistent with Apple's San Francisco family. Use:

1. `SF Pro Display` for 24 px page titles.
2. `SF Pro Text` for 12–14 px interface copy.
3. `-apple-system` as the implementation fallback.

Do not substitute Inter, Arial, a rounded display face, or a serif. Use regular and medium for almost everything. Semibold is reserved for the largest title or a currently selected primary action.

### Scale

| Role | Size | Line height | Weight | Tracking |
| --- | ---: | ---: | ---: | ---: |
| Mailbox/page title | 24 px | 30 px | 600 | -0.35 px |
| Conversation subject | 14 px | 19 px | 550 | -0.15 px |
| Body and primary row label | 13 px | 18 px | 450–550 | -0.15 px |
| Button/dropdown label | 13 px | 16 px | 550 | -0.15 px |
| Metadata, timestamps, key hints | 12 px | 16 px | 450–500 | -0.10 px |

Reference calibration: the source's `Personal` title is about 22 logical points, top dropdown labels about 13–14 points, and metadata about 12–13 points. Mail keeps its established 24/14/13/12 px product scale and uses the reference's weight and density.

### Typography rules

- Use sentence case everywhere.
- Use tabular numerals for unread counts and timestamps.
- Never use all caps for section labels.
- Keep body copy left aligned.
- Truncate message previews to one line; never shrink type to fit.
- Use a true ellipsis character where possible.
- Control labels stay optically centered, not mathematically overcorrected with arbitrary offsets.

## Spacing system

Use a 4 px base grid with the following allowed values:

- 2 px for paired metadata lines only.
- 4 px for icon/detail gaps.
- 6 px for compact keyboard chips.
- 8 px for control internals.
- 12 px for row groups and control clusters.
- 16 px for standard region padding.
- 20 px for window-aligned content padding.
- 24 px for major group separation.
- 32 px for desktop/window margin and modal breathing room.
- 48 px for reader content inset on wide layouts.

Avoid arbitrary 5, 7, 15, 18, 22, or 30 px gaps unless required for optical alignment.

## Desktop composition

### Canonical prototype viewport

- Design at **1440 × 900 px**.
- Keep 24–32 px of desktop ambience visible around the window.
- Recommended Mail window bounds: **x 28, y 24, width 1384, height 852**.
- Window radius: **28 px**.
- Minimum supported design width: **1120 px**.
- At narrower widths, preserve the sidebar and switch between inbox and reader rather than compressing into three unusable panes.

### Title bar

- Height: **52 px**.
- Traffic-light group begins 14 px from the left and 14 px from the top.
- Traffic light diameter: **12 px**; center gap: **8 px**.
- Use native red/yellow/green colors at restrained saturation.
- Place the current mailbox or conversation title at the optical center only when it does not compete with a contextual header below.
- The title bar is part of Depth 1 window glass, never an opaque strip.
- No browser address bar, tab strip, or fake URL.

### Primary layout

- Sidebar width: **232 px** at 1440 px; compact to **208 px** at the minimum width.
- Main content begins after a 1 px optical separation or a 12 px glass gutter, depending on state.
- Inbox uses the remaining width.
- Reader uses the remaining width with a centered content column capped at **960 px**.
- Preserve Mail's existing switch between the inbox list and focused reader.
- Do not turn the application into a generic three-column CRM or admin dashboard.

## Mail shell mapping

### Sidebar

The sidebar is a darker, quieter region of the same window material.

- Material: Depth 2 with a subtle `rgba(105, 151, 139, 0.08)` darkening overlay.
- Width: 232 px.
- Top padding below title bar: 20 px.
- Horizontal padding: 12 px.
- Navigation row: 36 px high, 8 px radius, 10 px horizontal inset.
- Icon: 14 px SF Symbol-equivalent, secondary ink.
- Label: 13 px regular; medium when active.
- Count: 12 px tabular, right aligned.
- Active row: Depth 3 selected glass; do not use a solid gray slab.
- Hover row: `rgba(239, 250, 246, 0.22)`.
- Label groups are separated by 16 px, not card containers.
- Bottom utility contains Gmail connection status and Command menu with a single faint top line.
- No logo tile beside the Mail name and no orange accent.

### Inbox header

- Height: **72–76 px**.
- Left padding: 20 px; right padding: 20 px.
- Title: 24 px medium/semibold.
- Count: 12 px muted, aligned to the title baseline.
- Right actions: Search and Compose, 8 px gap.
- Search is a raised light-glass button with `/` key hint.
- Compose is a dark near-black primary button with `C` key hint.
- Do not place actions inside a separate toolbar card.

### Message list

- Default row height: **60–64 px**.
- Horizontal padding: 20 px.
- Unread dot: 6 px, near-black.
- Sender column: 176–190 px.
- Sender and subject: 13 px medium when unread, regular when read.
- Preview: 13 px secondary ink, single-line truncation.
- Date: 12 px muted, 64 px right-aligned column.
- Divider: 1 px `--line-neutral`, inset to align with content where practical.
- Default row background: transparent.
- Hover: faint Depth 2 bright material.
- Keyboard selection: Depth 3 selected glass with 10–12 px radius and 4 px external inset. The selected row must still read as part of a list, not as a floating card.
- Star/archive affordances may appear on hover but cannot shift text columns.

### Keyboard footer

- Height: 40–44 px.
- Remains visually attached to the bottom of the window.
- Use a top optical edge, not a thick footer background.
- Key chips: 20 px high, 5–7 px radius, light glass, 1 px neutral edge.
- Show `J K Move`, `↵ Open`, `E Archive`, and `R Reply`.
- Metadata text: 12 px muted.

### Focused reader header

- Height: 72–76 px.
- Back button: 32 × 32 px hit area, simple chevron.
- Subject: 14 px medium.
- Sender/email line: 12 px muted.
- Archive and More use raised light-glass controls.
- More uses an ellipsis or downward chevron, not a large kebab menu button.
- Preserve 12 px gaps and align all controls to one center line.

### Conversation stack

- Background: transparent within a bright Depth 2 reader field.
- Content max width: 960 px.
- Wide horizontal inset: 48 px; compact inset: 24 px.
- Top padding: 16 px; bottom padding: 24 px.
- Collapsed message height: 52 px.
- Collapsed messages use very faint Depth 3 material, 14 px radius, 10 px vertical gap.
- Expanded message uses light Depth 3 material, 16 px radius, 16–20 px padding.
- Expanded body measure: maximum 720 px for comfortable reading.
- Use sender, recipient, date, and subject typography for hierarchy; no avatar badges are required.

### Persistent inline reply composer

This is a defining product component and must always be visible at the bottom of a loaded conversation.

- Material: light Depth 3 glass.
- Minimum height: **196–204 px**.
- Radius: **16 px**.
- Border: 1 px neutral optical edge plus 1 px inner highlight.
- Header: 40 px with `Reply to [sender]` in 12 px secondary ink.
- Editable field begins with at least 16 px horizontal and 14 px vertical padding.
- Footer: 44 px.
- Left controls: attachment `+` or paperclip, formatting `Aa`, then `Draft saved automatically`.
- Right controls: `⌘↵ Send` hint followed by the dark Send button.
- Send button: 32 px high, 11 px radius, near-black fill, white text.
- Attachments render as compact 28 px glass chips, never large file cards.
- The composer expands upward while maintaining its footer and keeping the newest content visible.

### Command menu

- Width: **560 px** at 1440 px viewport, maximum 40% of window width.
- Material: Depth 5.
- Radius: 18 px.
- Search field height: 48–52 px with no separate opaque input box.
- Results: 44 px rows, 8 px radius, 8 px panel padding.
- Selected command: near-black or deep green-black fill with light text.
- Command icon: 14 px; title 13 px medium; explanation 12 px secondary.
- Shortcut chip remains aligned at the far right.
- Footer: 40 px, faint top edge, compact navigation hints.
- Opening transition: opacity plus scale from 0.985 to 1 in 120 ms.

### Compose window

- Use the same Depth 5 material as the command menu.
- Keep it compact and centered or bottom-right, consistent with the existing Mail interaction.
- Recipient and subject fields use rows with faint bottom edges, not white input pills.
- Editor is an uninterrupted reading surface.
- Footer reuses attachment, formatting, schedule, keyboard hint, and primary send control patterns.

## Controls

### Light button

- 32 px height.
- 11 px continuous radius.
- 12 px horizontal padding.
- 13 px medium label.
- Optional icon at 12–14 px.
- Use Depth 4 material.
- Do not use pure opaque white.

### Primary button

- 32 px height; 11 px radius.
- Fill: `#17201C`.
- Hover: `#202B26`.
- Pressed: `#0E1512` with `transform: scale(0.985)`.
- Text: `--ink-on-dark`.
- Key hint uses 72% white, not a separate badge unless needed for alignment.

### Dropdown

- Use the same material as a light button.
- Label and chevron gap: 8 px.
- Chevron: 12 px, 1.75 px stroke, rounded line caps.
- The reference uses a stacked up/down selector for the account switcher. Mail should use a single down chevron for ordinary menus and reserve stacked chevrons for account cycling only.
- Menu aligns to the button's right edge.
- Menu vertical offset: 6 px.
- Menu item: 34–36 px high, 8 px radius.

### Search

- Collapsed state may be a 32 px `Search /` control.
- Expanded state is 36 px high, at least 240 px wide.
- Magnifier: 13 px.
- Placeholder: 13 px muted.
- Focus ring: 2 px translucent green, outside the 1 px optical edge.

### Keyboard chip

- Height: 20 px.
- Minimum width: 20 px.
- Radius: 6 px.
- Padding: 0 6 px.
- Font: 12 px regular with tabular metrics where available.
- Fill: `rgba(248, 252, 249, 0.54)`.
- Border: 1 px `--line-neutral`.

### Popover

- Width: 180–220 px for simple actions.
- Padding: 8 px.
- Radius: 14 px.
- Material: Depth 4 for anchored menus, Depth 5 for large palettes.
- Item height: 34 px.
- No arrow unless native platform behavior requires it.
- Selected item uses Depth 3 selected glass; destructive labels use semantic red text only.

## Iconography

- Use SF Symbols or icons drawn to the same optical proportions.
- Standard icon box: 16 × 16 px.
- Visible glyph size: 12–14 px.
- Stroke weight: roughly 1.25–1.75 px at 1×.
- Use rounded caps and joins.
- Icons inherit text color; do not introduce colorful glyphs.
- Avoid filled icons except the unread dot, active connection state, and rare status indication.
- The app icon or brand mark does not appear as a decorative tile inside the sidebar/header.

## State behavior

### Hover

- Increase local surface luminosity by 6–10%.
- Increase border contrast by no more than 4%.
- Do not lift rows with a large shadow.
- Hover reveals secondary row actions without moving primary content.

### Pressed

- Darken the glass slightly.
- Optional scale: 0.985 for buttons only.
- Duration: 90 ms.
- Avoid spring bounce.

### Keyboard focus

- Use a 2 px outer ring in `--focus-ring`.
- Maintain a 2 px gap between ring and control where space permits.
- Selection and focus may coexist; the focus ring must remain visible over selected glass.

### Selected

- Use Depth 3 selected glass.
- Increase primary text weight from regular to medium.
- Preserve text contrast and column alignment.
- Do not add a bright accent bar.

### Disabled

- Reduce content opacity to 42%.
- Keep the material at 65% of normal contrast.
- Remove shadow.
- Never rely on color alone.

### Loading

- Prefer stable skeleton rows with the same dimensions as content.
- Use a soft luminance pulse between 38% and 52% opacity over 900 ms.
- Do not use a large centered spinner for normal email loading.

## Motion

- Navigation and row hover: 90 ms.
- Button and dropdown state: 90–120 ms.
- Inbox-to-reader transition: 140 ms opacity plus 4 px horizontal movement.
- Popover/command menu: 120–140 ms opacity plus scale 0.985 → 1.
- Composer expansion: 140 ms ease-out.
- Use `cubic-bezier(0.2, 0.8, 0.2, 1)`.
- Respect reduced motion by removing translation and scale while preserving immediate opacity changes.
- No elastic bounce, parallax, animated gradients, or continuous floating.

## Density and content rules

- Fit at least 10 inbox rows at 1440 × 900 without reducing type below 12 px.
- Keep sender, subject, preview, and date aligned to stable columns.
- Avoid oversized empty states or marketing-style headlines.
- Use realistic concise email content in the mockup.
- Do not use lorem ipsum.
- Keep controls visible but quiet; keyboard hints can carry discoverability.
- A selected message should remain readable at a glance without demanding attention.

## Accessibility

- Primary text must reach at least 4.5:1 contrast against the composited glass.
- Secondary text must reach at least 4.5:1 when it conveys essential content.
- Frosted surfaces must have an opaque fallback for increased-contrast or reduced-transparency settings.
- Minimum pointer target: 32 × 32 px for compact desktop controls.
- Minimum keyboard focus target: the full visual control bounds.
- Every icon-only action requires an accessible label and tooltip.
- Do not encode read/unread only by the 6 px dot; use font weight as the second cue.
- Respect `prefers-reduced-motion` and, where available, platform reduced-transparency preferences.

## Responsive behavior

- **≥ 1280 px:** 232 px sidebar, full inbox columns, 48 px reader inset.
- **1120–1279 px:** 208 px sidebar, sender column 160 px, 24–32 px reader inset.
- **< 1120 px:** prototype may show a minimum-size boundary; do not redesign as mobile.
- Dropdowns and modals must remain within the clipped window.
- The persistent reply composer remains visible and never collapses into a floating action button.

## Do and do not

### Do

- Let the desktop ambience softly transmit through every major region.
- Use one coherent green-neutral glass family.
- Keep content geometry aligned to the existing Mail product.
- Reserve dark fill for the primary action and selected command.
- Use typography, spacing, and weight before borders or color.
- Keep the UI demonstrably keyboard-first.

### Do not

- Do not recreate the dock.
- Do not use the orange square, orange accent, or a white logo tile.
- Do not make every email a separate floating card.
- Do not use blue-purple SaaS gradients, neon edges, or glassmorphism clichés.
- Do not place white panels on top of a green glass shell.
- Do not add decorative charts, cards, tabs, widgets, or profile statistics.
- Do not hide the reply composer.
- Do not make the glass so transparent that wallpaper detail competes with text.
- Do not use blur alone; material also needs tint, border, highlight, and depth-calibrated shadow.

## Prototype interaction requirements

The Open Design mockup should include these connected states inside one product shell:

- Inbox with realistic read/unread messages and a visible keyboard selection.
- Focused conversation with collapsed history, expanded latest message, and persistent reply composer.
- Working navigation between inbox and focused conversation.
- Working sidebar mailbox selection.
- Working Search and Compose controls.
- Command menu triggered by `⌘K` or its visible control.
- Archive, More dropdown, Reply, and Send control states.
- Keyboard hints for `J`, `K`, `↵`, `E`, `R`, `C`, `/`, `⌘K`, `⌘↵`, and `Esc`.
- Hover, pressed, focus, selected, and disabled examples where those states clarify the system.

The mockup does not need live Gmail data or authentication. It must look and behave like an evaluable desktop Mail product, not a static marketing composition.

## Pixel-review checklist

- Outer window is one continuous 28 px-radius material with no square child leaking at corners.
- Desktop ambience remains visible on all four sides at 1440 × 900.
- Window blur, structural blur, nested blur, and control blur visibly decrease with depth.
- No orange or white logo tile is present.
- No dock or centered app-icon strip is present.
- Sidebar is 232 px and uses 36 px navigation rows.
- Inbox/reader header is 72–76 px.
- Message rows are 60–64 px and keep stable sender/subject/date columns.
- Type uses only 24, 14, 13, and 12 px product sizes.
- Standard buttons are 32 px high with 11 px radii.
- Major glass groups use 20 px radii; cards/composer use 16 px.
- Primary action is near-black, not orange, blue, or gradient-filled.
- Reader body is capped at 960 px and message copy at 720 px.
- Reply composer is always visible and at least 196 px high.
- Borders remain hairline and low contrast.
- Shadows are broad, cool, and diffuse.
- Every interactive control has a visible keyboard or focus state.
- The UI still reads instantly when the backdrop is visually busy.

## Acceptance statement

A successful redesign should be recognizable as the existing minimal Mail client before the viewer notices the new material treatment. It should then feel as though the entire product has been cast in the reference's layered frosted mint glass: calm, precise, native, and physically coherent. The design fails if the glass becomes the subject instead of the email.
