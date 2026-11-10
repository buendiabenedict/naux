import SwiftUI
import AVFoundation

@main
struct NauxApp: App {
    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Audio session setup failure is non-fatal for basic playback.
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
