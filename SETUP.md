# FlagSentry: build and setup

## Quick build (no Xcode project)
```
./build.sh                                   # builds build/FlagSentry.app
BUNDLE_ID=com.yourname.FlagSentry ./build.sh # custom bundle identifier
swift test                                   # runs the unit tests
```

## Xcode setup (alternative)

1. **New Project** → macOS → App. Product Name `FlagSentry`, Interface Storyboard, Language Swift, Bundle Identifier `com.example.FlagSentry`.
2. Delete the generated `AppDelegate.swift`, `ViewController.swift` and `Main.storyboard` (Move to Trash). Add `main.swift`, `AppDelegate.swift` and `Core.swift` from this folder (check Copy items if needed, target FlagSentry).
3. **Info.plist.** Target → Info → remove the `Main storyboard file base name` key. Replace the Info.plist contents with the file from `Info.plist` (or add the keys manually): `Application is agent (UIElement)` = YES and an ATS exception for `ip-api.com` → `NSExceptionAllowsInsecureHTTPLoads` = YES. Without the exception, HTTP requests are blocked. (The free ip-api.com tier is HTTP-only.)
4. **Signing & Capabilities.** Select a Team (or Sign to Run Locally). Add App Sandbox → Outgoing Connections (Client). Entitlements can be taken from `FlagSentry.entitlements`.
5. **Deployment Target** = macOS 13.0.
6. Build: Product → Build.

## Checking launch at login
1. Product → Show Build Folder in Finder → `Products/Debug/FlagSentry.app`, copy it to `/Applications`.
2. Quit the app and launch it from `/Applications` (not from Xcode).
3. System Settings → General → Login Items: FlagSentry should be listed and enabled. If it says "approval required", enable it manually. A registration error is shown in the status icon tooltip.
4. Log out and log back in: the flag appears by itself.
5. Check that it is not re-enabled: disable FlagSentry in Login Items, relaunch the app and make sure the switch stays off.
6. To repeat the first registration: `defaults delete com.example.FlagSentry autoLaunchRegistrationAttempted`.
