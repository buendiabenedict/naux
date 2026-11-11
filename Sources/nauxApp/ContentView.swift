import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()
    @State private var showImporter = false
    @State private var searchText = ""
    @State private var displayedTracks: [Track] = []
    @State private var isSearchBarVisible = true
    @State private var searchRequest = 0
    @FocusState private var searchFocused: Bool

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
                    PlayerBarView(player: player, playback: player.playback)
                }
            }
            .navigationTitle("naux")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        searchRequest += 1
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .tint(.blue)
                    .opacity(isSearchBarVisible && searchText.isEmpty ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isSearchBarVisible)
                    .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
                    .allowsHitTesting(!(isSearchBarVisible && searchText.isEmpty))

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
            .onAppear { updateDisplayedTracks() }
            .onChange(of: searchText) { _ in updateDisplayedTracks() }
            .onChange(of: player.tracks) { _ in updateDisplayedTracks() }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .onDisappear { player.cleanup() }
    }

    private func updateDisplayedTracks() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            displayedTracks = player.tracks
        } else {
            displayedTracks = player.tracks.filter { $0.title.localizedCaseInsensitiveContains(q) }
        }
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
        ScrollViewReader { proxy in
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Search music", text: $searchText)
                            .focused($searchFocused)
                            .foregroundStyle(.white)
                            .tint(.blue)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 10))
                    .listRowBackground(Color.black)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .id("search-bar")
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: SearchBarVisiblePreferenceKey.self,
                                value: geo.frame(in: .named("track-list")).maxY > 0
                            )
                        }
                    )

                    ForEach(displayedTracks) { track in
                        TrackRowView(
                            track: track,
                            selected: player.currentTrack?.id == track.id,
                            player: player
                        )
                        .listRowBackground(
                            Color(white: 0.12)
                                .overlay(Color(white: 0.24).opacity(player.currentTrack?.id == track.id ? 1 : 0))
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .coordinateSpace(name: "track-list")
            .onPreferenceChange(SearchBarVisiblePreferenceKey.self) { visible in
                isSearchBarVisible = visible
            }
            .onChange(of: searchRequest) { _ in
                withAnimation {
                    proxy.scrollTo("search-bar", anchor: .top)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    searchFocused = true
                }
            }
        }
    }
}

private struct SearchBarVisiblePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

private struct TrackRowView: View {
    let track: Track
    let selected: Bool
    @ObservedObject var player: PlayerViewModel

    var body: some View {
        Button {
            player.play(track)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(track: track, player: player, size: 48)
                Text(track.title)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerBarView: View {
    @ObservedObject var player: PlayerViewModel
    @ObservedObject var playback: PlaybackProgress

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                if let track = player.currentTrack {
                    ArtworkView(track: track, player: player, size: 44)
                } else {
                    ArtworkView(track: nil, player: player, size: 44)
                }
                Text(player.currentTrack?.title ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button(action: { player.togglePlay() }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                let total = max(playback.duration, 0.001)
                let fraction = min(max(playback.progress / total, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: geo.size.width * fraction, height: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, geo.size.width * fraction - 5))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard playback.duration > 0 else { return }
                            playback.isScrubbing = true
                            let x = min(max(value.location.x, 0), geo.size.width)
                            playback.progress = (x / geo.size.width) * total
                        }
                        .onEnded { value in
                            guard playback.duration > 0 else {
                                playback.isScrubbing = false
                                return
                            }
                            let x = min(max(value.location.x, 0), geo.size.width)
                            let time = (x / geo.size.width) * total
                            playback.progress = time
                            player.seek(to: time, endScrubbing: true)
                        }
                )
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color(white: 0.12))
        .overlay(alignment: .top) { Divider().background(Color.white.opacity(0.1)) }
    }
}

private struct ArtworkView: View {
    let track: Track?
    @ObservedObject var player: PlayerViewModel
    let size: CGFloat
    var cornerRadius: CGFloat = 8
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
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
        .task(id: track?.id) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let track else {
            image = nil
            return
        }
        if let data = player.cachedArtworkData(for: track.id) {
            image = UIImage(data: data)
            return
        }
        let data = await player.loadArtwork(for: track)
        guard !Task.isCancelled else { return }
        if let data {
            image = UIImage(data: data)
        } else {
            image = nil
        }
    }
}
