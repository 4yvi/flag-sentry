# FlagSentry: project notes

macOS menu-bar app (Swift, AppKit). Shows the flag of the current public IP's country, and posts a notification when the IP changes. No Xcode project.

## Files
- `main.swift`: entry point (accessory app, delegate kept in a top-level variable).
- `AppDelegate.swift`: UI (status item, menu), network monitor, 30 s timer, request flow, notifications, launch at login.
- `Core.swift`: pure logic with no AppKit: `ResponseParser` (validation/sanitizing), `Flag`, `IPChangeTracker`, `RateLimiter`, `NotificationText`.
- `Sources/FlagSentryCore/Core.swift`: symlink to `../../Core.swift` (so SwiftPM tests and `build.sh` share one source). Do not replace it with a copy.
- `Tests/FlagSentryTests/CoreTests.swift`: XCTest unit tests (24).
- `Package.swift`: used only for `swift test`.
- `build.sh`: builds `build/FlagSentry.app` with swiftc + ad-hoc signing. `BUNDLE_ID=... ./build.sh` overrides the bundle ID (default `io.github.4yvi.FlagSentry`).
- `Info.plist`, `FlagSentry.entitlements`: LSUIElement, ATS exception for ip-api.com, sandbox + network client.
- `SETUP.md`: build, Xcode setup and launch-at-login check instructions.

## Commands
```
swift test                      # unit tests
./build.sh                      # build the app
open build/FlagSentry.app       # run it (pkill -x FlagSentry first to restart)
rm -rf .build                   # clean SwiftPM artifacts
```
New logic that should be tested goes into `Core.swift`; a new source file must also be added to the `swiftc` line in `build.sh`.

## Decisions (keep these)
- All UI text, comments and docs are in English. Check with: `grep -rnP '[А-Яа-яЁё]' . --exclude-dir=build --exclude-dir=.build`.
- Notifications never contain the app name. Title is `IP changed to <country>` (or `IP changed` if the country is unknown); body is `<old> → <new> (<country>)`. The tooltip also has no app name.
- The endpoint stays plain HTTP `http://ip-api.com` on purpose: the free tier has no HTTPS and HTTPS alternatives have daily limits (~1000/day) below 30 s polling (~2880/day). This is explained in a comment above `endpoint`. Because of it, every response field is validated in `ResponseParser`.
- Rate limit: at most 1 request per 2 s (service limit is 45/min).
- Launch-at-login registration is retried until it succeeds once; the "attempted" flag is set only after success. If the user disables it later, it is not re-enabled.

## Known limitations
- `lastIP` is not saved between launches, so an IP change while the app is closed is not reported.
- Ad-hoc signing: `SMAppService` and notifications behave best when the app runs from `/Applications`.
- The app and notification flow was not verified by a live IP change (VPN toggle) in this session; only unit tests and a successful build and launch.
