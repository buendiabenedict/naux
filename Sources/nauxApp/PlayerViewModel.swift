import Foundation
import AVFoundation
import UIKit
import Combine
import MediaPlayer

struct Track: Identifiable, Equatable {
    let id: String
    let url: URL
    let title: String

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    var isScrubbing = false
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var volume: Double = 0.7 {
        didSet { player?.volume = Float(volume) }
    }
    @Published var folderName: String?
    @Published var errorMessage: String?

    let playback = PlaybackProgress()

    var progress: Double {
        get { playback.progress }
        set { playback.progress = newValue }
    }
    var duration: Double {
        get { playback.duration }
        set { playback.duration = newValue }
    }
    var isScrubbing: Bool {
        get { playback.isScrubbing }
        set { playback.isScrubbing = newValue }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: Any?
    private var folderURL: URL?
    private var hasFolderAccess = false
    private var remoteCommandsConfigured = false
    private var scanTask: Task<Void, Never>?
    private var artworkTasks: [String: Task<Void, Never>] = [:]
    private var artworkCache: [String: Data] = [:]
    private let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "aiff", "caf", "m4b", "alac"]
    private let bookmarkKey = "savedFolderBookmark"
    private let cacheKey = "savedFolderTrackCache"
    private let cachedFolderPathKey = "savedFolderTrackCachePath"

    init() {
        configureRemoteCommands()
        restoreSavedFolder()
    }

    private nonisolated func stopAccess(url: URL?) {
        guard let url else { return }
        url.stopAccessingSecurityScopedResource()
    }

    func cleanup() {
        scanTask?.cancel()
        scanTask = nil
        cancelArtworkTasks()
        removeObservers()
        if hasFolderAccess {
            stopAccess(url: folderURL)
        }
        hasFolderAccess = false
        folderURL = nil
        player?.pause()
        player = nil
    }

    func loadFolder(_ url: URL) {
        errorMessage = nil
        stopAccess(url: folderURL)
        folderURL = url
        hasFolderAccess = url.startAccessingSecurityScopedResource()
        folderName = url.lastPathComponent
        saveBookmark(for: url)
        loadCachedTracks(for: url)
        scanFolder(url, showLoadingMessage: tracks.isEmpty)
    }

    func reload() {
        guard let folderURL else { return }
        errorMessage = nil
        scanFolder(folderURL, showLoadingMessage: tracks.isEmpty)
    }

    private func restoreSavedFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            stopAccess(url: folderURL)
            folderURL = url
            hasFolderAccess = url.startAccessingSecurityScopedResource()
            folderName = url.lastPathComponent
            if isStale { saveBookmark(for: url) }
            if hasFolderAccess {
                loadCachedTracks(for: url)
                scanFolder(url, showLoadingMessage: tracks.isEmpty)
            } else {
                tracks = []
                stopPlayback(clearCurrent: true)
                errorMessage = "Could not access saved folder. Please select it again."
            }
        } catch {
            folderURL = nil
            hasFolderAccess = false
            folderName = nil
            tracks = []
            stopPlayback(clearCurrent: true)
            errorMessage = "Could not restore folder. Please select it again."
        }
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            // Ignore bookmark save failures; folder still works for this session.
        }
    }

    private func loadCachedTracks(for folder: URL) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: cachedFolderPathKey) == folder.path,
              let names = defaults.array(forKey: cacheKey) as? [String], !names.isEmpty else { return }
        let cached = names.compactMap { name -> Track? in
            let fileURL = folder.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
            return Track(id: fileURL.path, url: fileURL, title: fileURL.deletingPathExtension().lastPathComponent)
        }
        if !cached.isEmpty {
            tracks = cached
        }
    }

    private func saveTrackCache(for folder: URL, files: [URL]) {
        let names = files.map { $0.lastPathComponent }
        let defaults = UserDefaults.standard
        defaults.set(names, forKey: cacheKey)
        defaults.set(folder.path, forKey: cachedFolderPathKey)
    }

    private func scanFolder(_ url: URL, showLoadingMessage: Bool) {
        scanTask?.cancel()
        let folderPath = url.path
        let exts = audioExts
        scanTask = Task(priority: .userInitiated) {
            let result: Result<[URL], Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )
                    let audioFiles = files
                        .filter { exts.contains($0.pathExtension.lowercased()) }
                        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                    return .success(audioFiles)
                } catch {
                    return .failure(error)
                }
            }.value
            guard !Task.isCancelled else { return }
            guard self.folderURL?.path == folderPath else { return }
            switch result {
            case .success(let files):
                let newTracks = files.map { Track(id: $0.path, url: $0, title: $0.deletingPathExtension().lastPathComponent) }
                self.saveTrackCache(for: url, files: files)
                if self.tracks != newTracks {
                    self.reconcileCurrentTrack(with: newTracks)
                    self.tracks = newTracks
                }
                self.errorMessage = newTracks.isEmpty ? "No audio files found in this folder." : nil
                if newTracks.isEmpty {
                    self.stopPlayback(clearCurrent: true)
                } else {
                    self.pruneArtworkCache(validIDs: Set(newTracks.map(\.id)))
                }
            case .failure(let error):
                if self.tracks.isEmpty {
                    self.errorMessage = "Could not read folder: \(error.localizedDescription)"
                }
            }
        }
    }

    private func reconcileCurrentTrack(with newTracks: [Track]) {
        guard let current = currentTrack else { return }
        if let match = newTracks.first(where: { $0.id == current.id }) {
            currentTrack = match
        } else {
            stopPlayback(clearCurrent: true)
        }
    }

    func cachedArtworkData(for id: String) -> Data? {
        artworkCache[id]
    }

    func loadArtwork(for track: Track) async -> Data? {
        if let data = artworkCache[track.id] { return data }
        if let task = artworkTasks[track.id] {
            _ = await task.value
            return artworkCache[track.id]
        }
        let id = track.id
        let url = track.url
        let task = Task<Data?, Never>(priority: .utility) {
            await Task.detached(priority: .utility) {
                Self.extractArtwork(from: url)
            }.value
        }
        artworkTasks[id] = Task { _ = await task.value }
        let data = await task.value
        artworkTasks[id] = nil
        if let data {
            artworkCache[id] = data
            if currentTrack?.id == id {
                updateNowPlayingInfo()
            }
        }
        return data
    }

    func artwork(for track: Track) -> Data? {
        cachedArtworkData(for: track.id)
    }

    func loadArtworkIfNeeded(for track: Track) {
        guard artworkCache[track.id] == nil, artworkTasks[track.id] == nil else { return }
        Task { _ = await loadArtwork(for: track) }
    }

    private func pruneArtworkCache(validIDs: Set<String>) {
        artworkCache = artworkCache.filter { validIDs.contains($0.key) }
        for (id, task) in artworkTasks where !validIDs.contains(id) {
            task.cancel()
            artworkTasks[id] = nil
        }
    }

    private func cancelArtworkTasks() {
        for task in artworkTasks.values { task.cancel() }
        artworkTasks.removeAll()
    }

    private static nonisolated func extractArtwork(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let items = AVMetadataItem.metadataItems(from: asset.commonMetadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common)
        if let data = items.first?.dataValue { return data }
        for item in asset.metadata {
            if item.commonKey == AVMetadataKey.commonKeyArtwork, let data = item.dataValue { return data }
        }
        return nil
    }

    func play(_ track: Track) {
        guard tracks.contains(where: { $0.id == track.id }) else { return }
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
              let idx = tracks.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = (idx + 1) % tracks.count
        startPlayback(tracks[nextIndex])
    }

    func previous() {
        if playback.progress > 3 {
            seek(to: 0)
            return
        }
        guard !tracks.isEmpty, let current = currentTrack,
              let idx = tracks.firstIndex(where: { $0.id == current.id }) else { return }
        let prevIndex = (idx - 1 + tracks.count) % tracks.count
        startPlayback(tracks[prevIndex])
    }

    func seek(to time: Double, endScrubbing: Bool = false) {
        guard let player else {
            if endScrubbing { playback.isScrubbing = false }
            return
        }
        let target = max(0, min(time, playback.duration > 0 ? playback.duration : time))
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        playback.progress = target
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if endScrubbing { self.playback.isScrubbing = false }
                if !self.playback.isScrubbing { self.playback.progress = target }
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
        playback.progress = 0
        playback.duration = 0
        isPlaying = true
        addObservers(for: item)
        player?.play()
        updateNowPlayingInfo()
        loadArtworkIfNeeded(for: track)
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 { self.playback.duration = dur }
                if !self.playback.isScrubbing {
                    self.playback.progress = time.seconds.isFinite ? time.seconds : 0
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
        playback.progress = 0
        playback.duration = 0
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
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if playback.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = playback.duration
        }
        if let data = artworkCache[track.id], let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            loadArtworkIfNeeded(for: track)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playback.progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if playback.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = playback.duration
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
}
