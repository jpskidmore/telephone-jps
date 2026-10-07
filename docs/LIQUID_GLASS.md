# Compact macOS interface

Telephone is intended to stay open beside other desktop work. The 2.1.5 layout
uses the original Telephone window sizes as its starting point and the three
layouts selected for this fork: Icon rail, Dial bar with one recent call, and
Pocket card. Compactness comes from removing unused space and exposing secondary
controls on demand. Calling, recording, accounts, history and settings retain
their existing actions and data.

## Settings: Icon rail

General, Accounts, Sound and Network use a narrow, edge-to-edge navigation rail.
Its familiar system symbols have tooltips and accessible names; selection remains
visible without depending on color alone. Arrow keys navigate sections and Tab
moves into the form. Fields retain labels because an icon alone cannot explain a
setting reliably.

Since 2.1.6, every pane uses the Accounts pane's window size, keeping the frame
stable during navigation. The other forms are aligned within that shared size.
The selected Titled sections layout places General, Sound and Network 12 points
below the detail area's top edge and uses its full 548-point width. Native,
noneditable headings and separators group Calling / Recording, Devices &
ringtone / Call audio, and SIP & discovery / Outbound proxy. Their 16-point
leading inset and stable field columns keep related options aligned. Accounts
continues to fill the detail area. The frame remains 592 × 305 content points
(592 × 337 including the native titlebar on macOS 27).
Accounts retains the account list, detail tabs,
enabled-account editing restrictions and reordering. Sound retains its four
device/ringtone menus and codec setting. Leaving Network or closing its window
retains the existing Save, Cancel and Don't Save prompt.

The top-level Network section applies to all accounts. Accounts uses the name
Connection for its account-specific network options, with scope described in
help and accessible labels.

This placement follows Apple's [Layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout)
for important content near the top and leading edge, alignment and grouping
related items with space and separators. The exact spacing and fixed frame are
design choices for this app. The headings use the system font and label color,
expose native heading roles on macOS 26 and later (static text on older macOS),
and add no keyboard focus stops or glass surfaces.

Settings has a normal titled macOS window with its red Close button and
Command-W. Minimize and zoom remain disabled. The titlebar uses the opaque
semantic window background requested after 2.1.4 inspection. Desktop blending
begins below the titlebar, keeping background text out of the title and traffic
lights. Initial selection still waits until the full Settings hierarchy exists.

## Main window: Dial bar and one recent call

Availability, number entry, Call and history controls stay at the top. The
compact view shows the newest real history record underneath. Expanding history
uses the same records, selection and actions, including redial, deletion and
clearing. Contacts tokens and Return-to-call remain available. Account windows
remain separate; Availability continues to control registration status.

The compact window uses its own frame restoration identity so an old tall
history window does not defeat the new compact default. Expanded history remains
resizable. Secondary commands remain available through menus instead of taking
permanent space in the dial bar. The visible history button is the single
visibility control; More offers Clear Call History… without a duplicate toggle.

## Calls: Pocket card

The call card returns to the original 300-point width. Caller, number, status,
duration and recording state remain legible above a single row of icon controls:
Mute, Hold, Transfer, Keypad and End. Core call controls have 44-point hit targets,
tooltips and accessible action names. Enabled and selected states follow the
existing call lifecycle.

Incoming calls keep Answer and Decline. Ended calls keep Call Back and the
existing one-second redial guard. The on-demand keypad and physical keyboard
retain DTMF input, including A–D and R. Transfer sheets retain their existing
controllers. Closing a call window retains its existing end-call behavior;
floating-call preferences remain effective. Account identity, when enabled,
moves into the native window header rather than reserving a separate footer.

Status text can expand for long failures instead of permanently reserving a large
empty area. Useful caller and status text remains selectable. Icon controls use
semantic system colors and native focus/press/disabled behavior.

## Liquid Glass, appearance and accessibility

The control/navigation layer uses regular `NSGlassEffectView` on macOS 26 and
later, embedding controls through its documented `contentView`. The settings
rail runs to the window edges with square outer corners; compact control groups
use a modest rounded shape. Caller text, forms and history remain content rather
than extra layers of glass.

The underlying desktop-blending material is AppKit's
`NSVisualEffectMaterialUnderWindowBackground` with `BehindWindow` blending.
Regular glass preserves legibility; clear glass and custom opacity are not used
to force transparency. The app inherits macOS 27's native diffusion, material
intensity and Show Borders behavior. It introduces no competing glass slider or
changes to the user's system appearance preferences.

The deployment target remains macOS 15.6. Both SDK and runtime availability guard
native glass; earlier systems use semantic visual-effect materials. Reduce
Transparency uses an opaque semantic background, and Increase Contrast outlines
that fallback. Runtime material rebuilds retain keyboard focus and field-editor
selection. Light and Dark appearance use system fonts and semantic colors.
Settings uses a stable frame across sections. Action/accessibility strings are
supplied in UK English.

## Apple references

- [Platforms State of the Union, WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/) — macOS Liquid Glass refinements, system intensity and borders, edge-to-edge sidebars and compact toolbar treatment.
- [Modernize your AppKit app, WWDC26](https://developer.apple.com/videos/play/wwdc2026/289/) — current AppKit adoption guidance.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) and [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) — native control-layer material and composition.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) — sparing glass and readable content.
- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) and [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) — pane-sized settings and conventional window controls.
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) and [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help) — recognizable actions, input alternatives and tooltips.
- [Original Telephone source](https://github.com/64characters/Telephone) — compact account and call window geometry used as the baseline.

## Acceptance checks

Actual build and inspection evidence belongs in [VALIDATION.md](VALIDATION.md)
and the release's generated BUILD-VERIFICATION.md. This document records design
choices and required checks, not Apple certification.

- Inspect every Settings pane and account tab in Light and Dark appearance;
  check labels, focus order, close/reopen and Network save/cancel/discard.
- Check the compact dial bar with empty and populated history; expand and collapse
  full history while preserving selection, context-menu and keyboard actions.
- Check incoming, connecting, active and ended pocket cards, long identity/error
  text, recording, mute/hold, transfer, keypad and keyboard DTMF.
- Check Reduce Transparency, Increase Contrast and Reduce Motion while running,
  plus macOS 15.6 fallback and VoiceOver.
- Test real SIP and audio devices separately from layout and controller tests.
