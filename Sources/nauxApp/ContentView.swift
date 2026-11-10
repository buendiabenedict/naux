import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                trackList
                if player.currentTrack != nil {
                    nowPlaying
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [Color.black, Color(red: 0.12, green: 0.12, blue: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("naux")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Folder", systemImage: "folder")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        player.loadFolder(url)
                    }
                case .failure(let error):
                    player.errorMessage = error.localizedDescription
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .onDisappear { player.cleanup() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.folderName ?? "No folder selected")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(player.folderName == nil ? "Choose a folder with MP3 files" : "\(player.tracks.count) MP3\(player.tracks.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button("Choose Folder") { showImporter = true }
                    .buttonStyle(.borderedProminent)
            }

            if let error = player.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 8)
    }

    private var trackList: some View {
        Group {
            if player.tracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(player.folderName == nil ? "Select a folder to load your music" : "No MP3 files in this folder")
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(player.tracks) { track in
                        Button {
                            player.play(track)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: player.currentTrack?.id == track.id && player.isPlaying ? "speaker.wave.2.fill" : "music.note")
                                    .frame(width: 20)
                                    .foregroundStyle(player.currentTrack?.id == track.id ? .green : .white.opacity(0.7))
                                Text(track.title)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                if player.currentTrack?.id == track.id {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green.opacity(0.9))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.white.opacity(player.currentTrack?.id == track.id ? 0.12 : 0.04))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: 12) {
            Text(player.currentTrack?.title ?? "")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            VStack(spacing: 4) {
                Slider(value: $player.progress, in: 0...max(player.duration, 1)) { editing in
                    if !editing { player.seek(to: player.progress) }
                }
                .tint(.green)

                HStack {
                    Text(format(player.progress))
                    Spacer()
                    Text(format(max(player.duration, 0)))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
            }

            HStack(spacing: 36) {
                Button(action: player.previous) {
                    Image(systemName: "backward.fill").font(.title3)
                }
                Button(action: player.togglePlay) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                Button(action: player.next) {
                    Image(systemName: "forward.fill").font(.title3)
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(.white.opacity(0.6))
                Slider(value: $player.volume, in: 0...1).tint(.white.opacity(0.8))
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.white.opacity(0.6))
            }
            .font(.caption)
        }
        .padding(14)
        .background(.ultraThinMaterial.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
