import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()
    @State private var showImporter = false
    @State private var showFullPlayer = false
    @State private var blurTrackID: UUID?

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
                        .onTapGesture { showFullPlayer = true }
                }
            }
            .navigationTitle("naux")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        player.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(.blue)
                    .disabled(player.folderName == nil)

                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .tint(.blue)
                }
            }
            .background(Color.black.ignoresSafeArea())
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
        .preferredColorScheme(.dark)
        .tint(.white)
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(player: player)
        }
        .onDisappear { player.cleanup() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text(player.folderName == nil ? "No music loaded" : "No audio files")
                .font(.headline)
                .foregroundStyle(.white)
            Text(player.folderName == nil ? "Select a folder with your music." : "Choose another folder or reload.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Choose Folder") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
                .foregroundStyle(.white)
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
        .background(Color.black)
    }

    private var trackList: some View {
        List {
            ForEach(player.tracks) { track in
                Button {
                    blurTrackID = track.id
                    withAnimation(.easeInOut(duration: 0.2)) {
                        player.play(track)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if blurTrackID == track.id { blurTrackID = nil }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(data: track.artworkData, size: 48)
                        Text(track.title)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        if player.currentTrack?.id == track.id {
                            Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 4)
                    .blur(radius: blurTrackID == track.id ? 6 : 0)
                    .animation(.easeInOut(duration: 0.2), value: blurTrackID)
                }
                .listRowBackground(Color.black)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
    }

    private var playerBar: some View {
        HStack(spacing: 12) {
            ArtworkView(data: player.currentTrack?.artworkData, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(player.folderName ?? "")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button(action: { player.next() }) {
                Image(systemName: "forward.fill")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.12))
        .overlay(alignment: .top) { Divider().background(Color.white.opacity(0.1)) }
    }

}

private struct FullPlayerView: View {
    @ObservedObject var player: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            ZStack {
                trackDisplay
                    .id(player.currentTrack?.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .animation(.easeInOut(duration: 0.28), value: player.currentTrack?.id)

            VStack(spacing: 6) {
                Slider(value: $player.progress, in: 0...max(player.duration, 1)) { editing in
                    if !editing { player.seek(to: player.progress) }
                }
                .tint(.white)

                HStack {
                    Text(format(player.progress))
                    Spacer()
                    Text(format(max(player.duration, 0)))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
            }
            .padding(.horizontal, 24)

            HStack(spacing: 48) {
                Button(action: player.previous) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                Button(action: player.togglePlay) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.bottom, 24)
        .background(Color.black.ignoresSafeArea())
    }

    private var trackDisplay: some View {
        VStack(spacing: 20) {
            ArtworkView(data: player.currentTrack?.artworkData, size: min(UIScreen.main.bounds.width - 64, 320), cornerRadius: 16)
                .shadow(color: .black.opacity(0.4), radius: 20)

            VStack(spacing: 6) {
                Text(player.currentTrack?.title ?? "")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let folder = player.folderName {
                    Text(folder)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 24)
        }
        .blur(radius: 0)
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
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.2)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
