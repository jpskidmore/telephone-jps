# Security policy

## Supported release

Security fixes are applied to the current 2.x release. Older local builds are retained as historical artifacts but should not be treated as supported security releases.

## Reporting a vulnerability

Please use GitHub's private vulnerability-reporting feature for this repository when it is available. Do not put SIP credentials, call recordings, personal details, or a working exploit in a public issue.

Include the affected version/build, macOS version, reproduction steps, impact, and the smallest safe proof needed to demonstrate the problem. Remove or replace all real account and call data before sharing logs or examples.

## Scope notes

- Call recordings contain sensitive personal data and are stored with user-only permissions by the application.
- SIP and media security still depend on the configured SIP provider, transport, negotiated codecs, and network environment.
- The downloadable app is ad-hoc signed and is not Apple-notarized. Its main
  bundle uses an ad-hoc-only library-validation exception so it can load the
  bundled frameworks, which have no Apple Team ID. Normal project entitlements
  retain library validation for future Developer ID builds.
