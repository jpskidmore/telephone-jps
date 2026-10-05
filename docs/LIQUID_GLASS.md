# Liquid Glass and macOS interface changes in 2.1.3–2.1.4

The update uses AppKit's real `NSGlassEffectView` for call controls and Settings navigation on macOS 26 and later. It keeps the caller, call status, settings forms and call history on the content layer. This follows Apple's separation of controls/navigation from content rather than applying glass across an entire window.

## Visible material composition in 2.1.4

Local inspection found that regular glass over an ordinary white window looked
flat. Settings and the call windows now use the semantic
`NSVisualEffectMaterialUnderWindowBackground` with `BehindWindow` blending beneath
their content. This lets background colour visibly diffuse through the window,
while native regular Liquid Glass remains reserved for navigation and call
controls. The background is a standard AppKit material; the settings forms and
caller text are not wrapped in additional glass.

Settings keeps the standard native titlebar with a visible title and close
control. Its material fills the content area below that titlebar; the sidebar
and forms stay inside the window content layout guide. Minimize and zoom retain
the disabled behavior appropriate to a pane-sized Settings window. The call
backdrop is inserted underneath the existing content and account footer,
preserving their geometry. Reduce Transparency switches the backdrop and window
to an opaque semantic background without detaching forms. A material rebuild
restores keyboard focus and field-editor selection for affected controls.

Regular glass is retained because the sidebar contains text and navigation.
Apple reserves clear glass for media-rich backgrounds; reducing opacity by
forcing clear glass or a custom alpha would weaken this text-heavy interface.
No user appearance or accessibility preferences are changed.

## Two substantial GUI improvements

1. **Call hierarchy and discoverable controls.** Incoming, active and ended calls share a spacious layout, a 22-point system caller heading, a separate two-line status label, and a glass control area. Tiny icon-only end/redial controls become labeled native buttons with SF Symbols. Active calls expose the existing Mute/Unmute, Hold/Resume and Transfer commands; their enabled states and labels use the existing menu validation. The four actions form two rows, with width calculated from the native buttons' fitting sizes so translated labels fit. End Call stays visible during connection; its original enabled/disabled lifecycle remains authoritative. Recording remains a red indicator with an explicit accessible description.
2. **Persistent native Settings navigation.** A source-list sidebar replaces the horizontal preference toolbar. General, Accounts, Sound and Network retain their existing view controllers, forms, bindings and actions. The sidebar uses system selection, accent colors, SF Symbols and the user's default sidebar row size. Keyboard arrow navigation keeps focus in the sidebar; Tab moves into the settings controls. Programmatic navigation to Accounts still focuses the accounts table. The same Network save/cancel/discard prompt remains active when changing section or closing the window. The app menu now says Settings… and keeps the original Command-comma shortcut and action.

The existing DTMF responder, SIP state transitions, call handling, recording and transfer-sheet controllers remain in use. The dedicated transfer sheet nibs retain their original layouts.

## Compatibility and accessibility

- Deployment target remains macOS 15.6. API use is guarded both by the compile-time SDK version and `@available(macOS 26.0, *)`.
- On macOS 26+, the regular glass effect embeds controls through its `contentView`, the documented composition API. It uses no custom tint and no macOS 27-only APIs.
- macOS 15.6 uses a semantic `NSVisualEffectView` material: sidebar for navigation and popover for call controls.
- Reduce Transparency replaces the custom material with an opaque system window background, and Increase Contrast adds a separator outline to that fallback. Changes to accessibility display options are observed at runtime on the main thread.
- Dynamic system fonts and semantic label/accent/destructive colors adapt to appearance. Controls retain native press, disabled, focus and accessibility behavior.
- Caller/status text can be selected and copied. Buttons have labels/tooltips; decorative symbols are excluded from accessibility. New interface/accessibility strings are provided in English, German and Russian.
- The material helper introduces no animation. Settings window resizing respects Reduce Motion; existing call-window transition behavior is retained.

## Apple references

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) — use standard system components and reserve glass for the navigation/control layer.
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) — native AppKit material and content embedding.
- [UnderWindowBackground](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground) and [BehindWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow) — semantic window backdrop and desktop blending.
- [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/) — native content embedding, glass hierarchy and titlebar/sidebar layout.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) — semantic material choice and legibility.
- [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) and [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) — recognizable system window controls and disabled minimize/zoom for Settings.
- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) — peer section navigation, familiar symbols and system sidebar sizing.
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) — clear action labels, native controls and action hierarchy.
- [Labels](https://developer.apple.com/design/human-interface-guidelines/labels) — system typography, semantic text colors and selectable useful text.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) and [Color](https://developer.apple.com/design/human-interface-guidelines/color) — accessible input, appearance adaptation and meaning beyond color.

## Validation and local acceptance

A standalone compilation of the new helper passed against the local AppKit SDK with a macOS 15.6 deployment target. A temporary offscreen AppKit harness checked native glass composition and call layout geometry. These are component checks, not a substitute for launching the built app or making calls. Current build and regression status is tracked in [VALIDATION.md](VALIDATION.md).

After installing the test build, check:

- Light and Dark appearance; translucent desktop/content behind call controls; Reduce Transparency and Increase Contrast on/off while the app runs.
- English/German/Russian labels, a long caller name, a two-line failure message, and the recording indicator; no clipping or overlap.
- Incoming Answer/Decline; outgoing Connecting/End Call; active Mute/Unmute, Hold/Resume, Transfer and DTMF; ended Call Back; automatic recording and the existing transfer sheets.
- Settings with mouse, sidebar arrow keys, Tab and VoiceOver. Verify the selected section, accessible action names, copyable caller/status labels and disabled controls.
- Settings shows its title and native red close control when active. Click that control, reopen with Command-comma, then verify Command-W closes it as well.
- Network edit followed by another section or window close: Save, Cancel and Don't Save. Cancel keeps Network selected and its pending edits intact.
- macOS 15.6 fallback in addition to macOS 26+ native glass; Reduce Motion during Settings section changes.

Full manual VoiceOver, OS fallback and live SIP/audio checks require the local test build and configured accounts. This document records the design decisions and acceptance criteria; it does not claim Apple certification.
