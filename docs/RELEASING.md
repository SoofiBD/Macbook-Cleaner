# Release checklist

1. Run the complete local suite documented in `CONTRIBUTING.md` and require the
   macOS 14 / Python 3.10 and macOS 15 / Python 3.14 CI matrix to pass.
2. Update `VERSION` in `clean_mac.sh` and the release tag in
   `Formula/apple-cleanup.rb` to the same semantic version.
3. Create the source archive from the final tagged commit. Compute SHA-256 from
   that immutable archive; never reuse a checksum from a working tree or a
   mutable branch.
4. Put that checksum in `Formula/apple-cleanup.rb`, then run `brew audit`,
   `brew install --build-from-source`, the Formula test, and both launch modes.
5. Verify `--scan-json`, one `--scan-category-json` request, Preview cleanup,
   Health, cancellation, operation history, restore, weekly enable/disable,
   upgrade, and `--remove-user-data` on a disposable macOS account.
6. Publish the tag and release notes only after the Formula points to the exact
   tag and checksum. Re-run CI on the tag before announcing the release.

The repository Formula may continue to point at the latest published release
while unreleased changes are developed. Do not change its URL or checksum until
the corresponding immutable tag exists.
