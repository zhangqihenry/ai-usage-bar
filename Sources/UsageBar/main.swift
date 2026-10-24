import AppKit

// `main.swift` is the only file allowed to contain top level code in a SwiftPM
// executable target, which is why the AppKit bootstrap lives here instead of
// using an `@main` type.
//
// Order matters: CLI flags are handled before any AppKit object is created so
// `usagebar --print` works over SSH and in CI, where no window server session
// exists.

if CLI.isRequested {
    CLI.run() // never returns
}

let application = NSApplication.shared
// Top level code is not actor isolated, but `AppDelegate` is @MainActor (AppKit
// requires it). Main is guaranteed here: `main.swift` runs on the main thread
// before the run loop starts.
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate

// `.accessory`: menu bar only, no Dock icon, no app switcher entry. The same
// flag is set via LSUIElement in Info.plist so the Dock icon never flashes
// during launch.
application.setActivationPolicy(.accessory)
application.run()
