## Description

<!-- What does this PR change, and why? -->

## Related issue

<!-- e.g. Closes #123 -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Refactor / cleanup (no behavior change)

## Checklist

### Architecture (no-dependency / no-compiler philosophy)

- [ ] Does **not** add external npm/pip dependencies.
- [ ] Does **not** add a CDN link or any external network request.
- [ ] Does **not** introduce a build step or compiler (frontend stays vanilla JS).
- [ ] Any GSAP/animation code remains locally vendored in `web/vendor/`.

### Testing

- [ ] I ran ShellCheck on `clean_mac.sh` (`shellcheck --shell=bash clean_mac.sh`).
- [ ] Python tests pass (`python3 -m unittest discover -s tests -p "test_*.py"`).
- [ ] JS tests pass (`node --test tests/`).
- [ ] I smoke-tested the dashboard / launcher where relevant.

### Quality

- [ ] The change is focused and scoped to one logical concern.
- [ ] I added or updated tests for my change where it makes sense.
- [ ] I updated documentation (README / CONTRIBUTING) if behavior changed.

## Screenshots / notes

<!-- Optional: UI screenshots, edge cases, or anything reviewers should know. -->
