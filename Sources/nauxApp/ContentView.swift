import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if player.tracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
            }
            .safeAreaInset(edge: .bottom) {
                if player.currentTrack != nil {
                    playerBar
                }
            }
            .navigationTitle("naux")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Reload", systemImage: "arrow.clockwise") { player.reload() }
                        .disabled(player.folderName == nil)
                    Button("Folder", systemImage: "folder") { showImporter = true }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { player.loadFolder(url) }
                case .failure(let error):
                    player.errorMessage = error.localizedDescription
                }
            }
        }
        .onDisappear { player.cleanup() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(player.folderName == nil ? "No music loaded" : "No audio files")
                .font(.headline)
            Text(player.folderName == nil ? "Select a folder with your music." : "Choose another folder or reload.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Folder") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            if let error = player.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackList: some View {
        List {
            if let folder = player.folderName {
                Section {
                    Text(folder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(player.tracks) { track in
                    Button { player.play(track) } label: {
                        HStack(spacing: 12) {
                            ArtworkView(data: track.artworkData, size: 44)
                            Text(track.title)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if player.currentTrack?.id == track.id {
                                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var playerBar: some View {
        VStack(spacing: 8) {
            Slider(value: $player.progress, in: 0...max(player.duration, 1)) { editing in
                if !editing { player.seek(to: player.progress) }
            }

            HStack(spacing: 12) {
                ArtworkView(data: player.currentTrack?.artworkData, size: 40)
                Text(player.currentTrack?.title ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Button(action: player.previous) {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)

                Button(action: player.togglePlay) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(format(player.progress))
                Spacer()
                Text(format(max(player.duration, 0)))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
