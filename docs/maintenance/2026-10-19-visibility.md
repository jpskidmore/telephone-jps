# Repository visibility restored — issue #53

On 19 October 2026 the owner authorised execution of the ranked roadmap, one
issue at a time. The first item used option A: restore the private visibility
already required by `AGENTS.md`. GitHub now reports `private: true` and
`visibility: private`; authenticated owner access still has administrator,
maintain, push and pull permissions.

The before/after check found no Pages site and no forks. All 11 release records,
60 uploaded asset records (IDs, names, sizes, digest metadata and states), 11
remote tag references and three existing local tag references are unchanged.
The eight remote-only tags were already absent locally; no fetch or tag rewrite
was needed. Access role/permission aggregates also match; collaborator and team
identities were deliberately excluded from the saved comparison.

Anonymous requests to the repository web page, repository API and v3.5.1 release
page return HTTP 404. Authenticated download of the 539-byte v3.5.1
`SHA256SUMS.txt` works and matches its recorded SHA-256:
`520fef78918a81c8fede5b9378ee1dcf277d06af3bc19e1269b2304e7da66587`.

The [machine-readable comparison](issue-53-verification.json) records these
checks and the matching manifest hashes. Asset metadata comparisons are not a
fresh download/hash verification of every app archive. No application source,
build, installation, user data, release tag or uploaded asset changed. The app
remains 3.5.1/build 163; no live-call or macOS runtime acceptance is claimed by
this repository-settings repair.

## References

- [Issue #53](https://github.com/jpskidmore/telephone-jps/issues/53) and
  [ranked roadmap](https://github.com/jpskidmore/telephone-jps/issues/52).
- [GitHub repository visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)
  — visibility implications reviewed before the change.
- [OpenAI Codex best practices](https://learn.chatgpt.com/guides/best-practices)
  — scoped work and explicit verification; no OpenAI runtime integration.
- [Apple macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
  — compatibility reference; this change affects no macOS API or application UI.
