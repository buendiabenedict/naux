import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()
    @State private var showImporter = false
    @State private var showFullPlayer = false
    @State private var searchText = ""

    private var filteredTracks: [Track] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return player.tracks }
        return player.tracks.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search music")
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
            Section {
                ForEach(filteredTracks) { track in
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            player.play(track)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(data: track.artworkData, size: 48)
                            Text(track.title)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(player.currentTrack?.id == track.id ? Color.blue.opacity(0.35) : Color(white: 0.12))
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .animation(.easeInOut(duration: 0.25), value: player.currentTrack?.id)
        .animation(.easeInOut(duration: 0.2), value: searchText)
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
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
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
    @State private var isSeeking = false
    @State private var seekValue: Double = 0
    @State private var transitionForward = true

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 24)

            ZStack {
                trackDisplay
                    .id(player.currentTrack?.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: transitionForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: transitionForward ? .leading : .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96))
                    ))
            }
            .animation(.easeInOut(duration: 0.3), value: player.currentTrack?.id)
            .clipped()

            Spacer()

            HStack(spacing: 48) {
                Button {
                    transitionForward = false
                    withAnimation(.easeInOut(duration: 0.3)) { player.previous() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                Button(action: player.togglePlay) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                Button {
                    transitionForward = true
                    withAnimation(.easeInOut(duration: 0.3)) { player.next() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)

            Spacer().frame(height: 32)
        }
        .padding(.bottom, 24)
        .background(Color.black.ignoresSafeArea())
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 90 && abs(value.translation.width) < 120 {
                        dismiss()
                    }
                }
        )
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
                    Color(white: 0.22)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
