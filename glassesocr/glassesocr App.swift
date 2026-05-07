// filename: glassesocr app.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis
// date: may 7 2026

import SwiftUI
import MWDATCore

@main
struct glassesocr_App: App {

    // tracks whether wearables sdk has finished its async init
    // mainappview is gated behind this to prevent calls into uninitialized sdk
    @State private var sdkReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if sdkReady {
                    MainAppView()
                } else {
                    // shown briefly while wearables.configure runs
                    ProgressView("Initializing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.surface)
                        .task {
                            try? Wearables.configure()
                            sdkReady = true
                        }
                }
            }
            // theme palette is built around cream and teal
            // dark mode would invert primary text colors and break contrast
            .preferredColorScheme(.light)
        }
    }
}
