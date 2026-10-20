# Numbering version and coverage — issue #60

Show prefixes now starts with the exact bundled numbering version, identifies
the saved country and lists the supported home-country profiles from the source
constants. It explains offline range coverage and does not imply live provider
prices, allocation or reachability. The existing native sheet remains bounded
and scrollable, with the actual backend prefix lists after the explanation.

The Routes footer follows the draft country. For non-UK profiles it explains
that domestic telephone numbers use Other and Mobile/Landline/Premium range
classification is UK-only. Native tooltips and accessibility help retain the
separate short/service/emergency rules, longest-prefix precedence and no
fallback. The prefix sheet continues using saved values until Save.

A damaged or future-format saved plan is labelled as needing repair. Its sheet
describes the displayed repair country rather than claiming those defaults were
validly saved. An unsaved repair country may differ; stored bytes remain intact
and routing stays blocked. The footer correctly asks the owner to repair/save
to update the list. No classification, provider routing or metadata is changed.

The complete literal R/P explanation was delivered by #59. This change adds
native coverage of ready, waiting, Offline and blocked previews so successful
readiness does not hide the provider-syntax limitation.

## Fresh local verification — 20 October 2026

- **329 app cases passed, zero failures:** 281 XCTest plus 48 Swift Testing.
  Four new editor cases exercise all five home-country profiles, saved versus
  draft countries, corrupt/future-format data and R/P guidance. The focused
  editor run passed **21 cases** after the final repair-footer wording change.
- Light/Dark native layout assertions preserve the 548 × 292 pane, all route
  selectors and the 484 × 244 prefix sheet. Exact metadata version, initial
  text position, wrapping/scrolling, readable footer width and accessibility
  metadata are checked. Prefix lists still come from the saved backend plan.
- Independent review found no remaining blockers; whitespace checks and the
  historical 50-issue repair gate passed. The routing model, admission
  coordinator, shared dialler, standalone harness and project metadata are
  unchanged. The 213 routing/presentation assertions passed under #59 and were
  not rerun for this UI-only change.

The [JSON record](issue-60-verification.json) binds source and logs. Tests used a
fresh unique nib-free Debug host, actual Telephone app-module editor types,
synthetic accounts and isolated defaults. Inspected native view-cache images
support some text-fit checks, but one Light capture was blank and composited
button/menu titles are incomplete. Those images do not establish full visual
acceptance. Proficient VoiceOver and actual provider/device/audio/permission
acceptance remain separate under [#62](https://github.com/jpskidmore/telephone-jps/issues/62)
and the final release.

This source fix does not install, publish or bump the version. Installed baseline
remains **3.5.1/build 163**, with combined delivery after the roadmap. User data,
credentials and release tags/assets are preserved; no cloud workflows ran.

Official documentation checked on 20 October:
[OpenAI best practices](https://learn.chatgpt.com/docs/learn/best-practices),
[Apple macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
and [NSAccessibilityProtocol](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol).
Standard AppKit information/help properties retain the macOS 15.6 baseline;
no OpenAI runtime dependency or new macOS-only API is introduced.
