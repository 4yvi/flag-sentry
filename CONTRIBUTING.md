# Contributing

Thanks for your interest in FlagSentry!

## Getting started

```
git clone https://github.com/4yvi/flag-sentry.git
cd flag-sentry
swift test
./build.sh && open build/FlagSentry.app
```

## Guidelines

- Open an issue first for larger changes so we can agree on the approach.
- Keep logic that does not need AppKit in `Core.swift` and cover it with tests in `Tests/FlagSentryTests`.
- `Sources/FlagSentryCore/Core.swift` is a symlink to `../../Core.swift`. Do not replace it with a copy.
- A new source file must also be added to the `swiftc` line in `build.sh`.
- All UI text, comments and docs are in English.
- Do not put the app name in notifications or tooltips.
- Use clear, imperative commit messages (Conventional Commits are welcome: `feat:`, `fix:`, `docs:`).
- Make sure `swift test` and `./build.sh` pass before opening a pull request.

See [NOTES.md](NOTES.md) for design decisions that should be kept.
