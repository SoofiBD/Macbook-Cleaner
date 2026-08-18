# Release checklist

1. Run the complete local suite documented in `CONTRIBUTING.md` and require the
   macOS 14 / Python 3.10 and macOS 15 / Python 3.14 CI matrix to pass.
2. Update the canonical `VERSION` in `clean_mac.sh`. The dashboard reads this
   value at startup, so the CLI, server banner, status API, and footer stay in
   sync. Commit the release candidate and require CI to pass.
3. Create and push the immutable semantic-version tag from that exact commit,
   but do not announce the GitHub release yet. Download GitHub's generated tag
   archive and compute its SHA-256; never reuse a checksum from a working tree,
   local `git archive`, or a mutable branch.
4. Update the URL and checksum in `Formula/apple-cleanup.rb` to the new tag in
   a follow-up commit. Then run `brew audit`, `brew install --build-from-source`,
   the Formula test, and both launch modes.
5. Verify `--scan-json`, one `--scan-category-json` request, Preview cleanup,
   Health, cancellation, operation history, restore, weekly enable/disable,
   upgrade, and `--remove-user-data` on a disposable macOS account.
6. Publish the GitHub release notes only after the Formula points to the exact
   tag and checksum. Re-run CI on both the tag and Formula update before
   announcing the release.

The repository Formula may continue to point at the latest published release
while unreleased changes are developed. Do not change its URL or checksum until
the corresponding immutable tag exists.
