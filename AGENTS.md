Use `master` for the working branch, upstream and default branch. Never introduce a `main` branch.

Keep signing keys, passwords and generated build products out of Git. The direct-download release pipeline is in `scripts/release.sh`; publishing a GitHub release is a separate action.

Validate C changes with `make test-sanitize`, Swift animation/worker changes with `swift test --arch arm64`, and release scripts with `python3 -m unittest discover -s tests/release -v`. UI changes also require the macOS app/UI CI checks.
