import Foundation
import AVFoundation
import Combine

struct Track: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.7 {
        didSet { player?.volume = Float(volume) }
    }
    @Published var folderName: String?
    @Published var errorMessage: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: Any?
    private var folderURL: URL?
    private var hasFolderAccess = false

    deinit {
        removeObservers()
        stopFolderAccess()
    }

    func loadFolder(_ url: URL) {
        errorMessage = nil
        stopFolderAccess()
        folderURL = url
        hasFolderAccess = url.startAccessingSecurityScopedResource()
        folderName = url.lastPathComponent

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let mp3s = files
                .filter { $0.pathExtension.lowercased() == "mp3" }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

            tracks = mp3s.map { Track(url: $0, title: $0.deletingPathExtension().lastPathComponent) }

            if tracks.isEmpty {
                errorMessage = "No MP3 files found in this folder."
                stopPlayback(clearCurrent: true)
            } else {
                stopPlayback(clearCurrent: true)
            }
        } catch {
            tracks = []
            stopPlayback(clearCurrent: true)
            errorMessage = "Could not read folder: \(error.localizedDescription)"
        }
    }

    func play(_ track: Track) {
        guard tracks.contains(track) else { return }
        if currentTrack?.id == track.id {
            togglePlay()
            return
        }
        startPlayback(track)
    }

    func togglePlay() {
        guard let player else {
            if let first = tracks.first { startPlayback(first) }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.volume = Float(volume)
            isPlaying = true
        }
    }

    func next() {
        guard !tracks.isEmpty, let current = currentTrack,
              let idx = tracks.firstIndex(of: current) else { return }
        let nextIndex = (idx + 1) % tracks.count
        startPlayback(tracks[nextIndex])
    }

    func previous() {
        if progress > 3 {
            seek(to: 0)
            return
        }
        guard !tracks.isEmpty, let current = currentTrack,
              let idx = tracks.firstIndex(of: current) else { return }
        let prevIndex = (idx - 1 + tracks.count) % tracks.count
        startPlayback(tracks[prevIndex])
    }

    func seek(to time: Double) {
        guard let player else { return }
        let target = max(0, time)
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        progress = target
    }

    private func startPlayback(_ track: Track) {
        removeObservers()
        let item = AVPlayerItem(url: track.url)
        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.volume = Float(volume)
        currentTrack = track
        progress = 0
        duration = 0
        isPlaying = true
        addObservers(for: item)
        player?.play()
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.progress = time.seconds.isFinite ? time.seconds : 0
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 { self.duration = dur }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.next()
            }
        }
    }

    private func stopPlayback(clearCurrent: Bool) {
        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        progress = 0
        duration = 0
        if clearCurrent { currentTrack = nil }
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func stopFolderAccess() {
        if hasFolderAccess, let folderURL {
            folderURL.stopAccessingSecurityScopedResource()
        }
        hasFolderAccess = false
    }
}
