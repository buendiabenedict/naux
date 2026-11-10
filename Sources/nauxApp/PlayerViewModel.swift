import Foundation
import AVFoundation
import UIKit
import Combine
import MediaPlayer

struct Track: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String
    let artworkData: Data?

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
    var isScrubbing = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: Any?
    private var folderURL: URL?
    private var hasFolderAccess = false
    private var remoteCommandsConfigured = false

    init() {
        configureRemoteCommands()
    }

    private nonisolated func stopFolderAccess(url: URL?) {
        guard let url else { return }
        url.stopAccessingSecurityScopedResource()
    }

    func cleanup() {
        removeObservers()
        if hasFolderAccess {
            stopFolderAccess(url: folderURL)
        }
        hasFolderAccess = false
        folderURL = nil
        player?.pause()
        player = nil
    }

    func loadFolder(_ url: URL) {
        errorMessage = nil
        stopFolderAccess()
        folderURL = url
        hasFolderAccess = url.startAccessingSecurityScopedResource()
        folderName = url.lastPathComponent
        scanFolder(url)
    }

    func reload() {
        guard let folderURL else { return }
        errorMessage = nil
        scanFolder(folderURL)
    }

    private func scanFolder(_ url: URL) {
        let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "aiff", "caf", "m4b", "alac"]
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let audioFiles = files
                .filter { audioExts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

            tracks = audioFiles.map { file in
                Track(
                    url: file,
                    title: file.deletingPathExtension().lastPathComponent,
                    artworkData: Self.extractArtwork(from: file)
                )
            }

            if tracks.isEmpty {
                errorMessage = "No audio files found in this folder."
            }
            stopPlayback(clearCurrent: true)
        } catch {
            tracks = []
            stopPlayback(clearCurrent: true)
            errorMessage = "Could not read folder: \(error.localizedDescription)"
        }
    }

    private static func extractArtwork(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let items = AVMetadataItem.metadataItems(from: asset.commonMetadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common)
        if let data = items.first?.dataValue { return data }
        for item in asset.metadata {
            if item.commonKey == AVMetadataKey.commonKeyArtwork, let data = item.dataValue { return data }
        }
        return nil
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
        updateNowPlayingInfo()
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
        let target = max(0, min(time, duration > 0 ? duration : time))
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        progress = target
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isScrubbing { self.progress = target }
                self.updateNowPlayingInfo()
            }
        }
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
        updateNowPlayingInfo()
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 { self.duration = dur }
                if !self.isScrubbing {
                    self.progress = time.seconds.isFinite ? time.seconds : 0
                }
                self.updateNowPlayingPlaybackTime()
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
        if clearCurrent {
            currentTrack = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        } else {
            updateNowPlayingInfo()
        }
    }

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPlaying { self.togglePlay() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying { self.togglePlay() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let data = track.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
        if hasFolderAccess {
            stopFolderAccess(url: folderURL)
        }
        hasFolderAccess = false
        folderURL = nil
    }
}
