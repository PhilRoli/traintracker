// Sources/TrainTracker/main.swift
import AppKit

// main.swift is the app entry point; AppKit objects must be used on the main
// actor, so we assert isolation here — this runs on the main thread by definition.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
