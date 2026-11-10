import AppKit

let app = NSApplication.shared
// The delegate is kept in a top-level variable, otherwise NSApplication (weak reference) would not retain it.
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
