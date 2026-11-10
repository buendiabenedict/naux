import Foundation
import AVFoundation
import Combine

struct Track: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 180
    @Published var volume: Double = 0.7

    private let tracks: [Track] = [
        Track(title: "Midnight Drive", artist: "naux"),
        Track(title: "Soft Static", artist: "naux"),
        Track(title: "Glass Echoes", artist: "naux")
    ]
    private var index = 0
    private var timer: AnyCancellable?

    var currentTrack: Track { tracks[index] }

    init() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func togglePlay() {
        isPlaying.toggle()
    }

    func next() {
        index = (index + 1) % tracks.count
        progress = 0
    }

    func previous() {
        if progress > 3 {
            progress = 0
        } else {
            index = (index - 1 + tracks.count) % tracks.count
            progress = 0
        }
    }

    func seek(to time: Double) {
        progress = min(max(time, 0), duration)
    }

    private func tick() {
        guard isPlaying else { return }
        if progress < duration {
            progress = min(progress + 0.5, duration)
        } else {
            next()
        }
    }
}
