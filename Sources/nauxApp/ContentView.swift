import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AVKit

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()
    @State private var showImporter = false
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
                }
            }
            .navigationTitle("naux")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search music")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    RoutePickerButton()
                        .frame(width: 30, height: 30)

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
                    let selected = player.currentTrack?.id == track.id
                    Button {
                        player.play(track)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(data: player.artwork(for: track), size: 48)
                                .onAppear { player.loadArtworkIfNeeded(for: track) }
                            Text(track.title)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        Color(white: 0.12)
                            .overlay(Color(white: 0.24).opacity(selected ? 1 : 0))
                            .animation(.easeInOut(duration: 0.3), value: selected)
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                    .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: searchText)
    }

    private var playerBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ArtworkView(data: player.currentTrack.flatMap { player.artwork(for: $0) }, size: 44)
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
                let total = max(player.duration, 0.001)
                let fraction = min(max(player.progress / total, 0), 1)
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
                            guard player.duration > 0 else { return }
                            player.isScrubbing = true
                            let x = min(max(value.location.x, 0), geo.size.width)
                            player.progress = (x / geo.size.width) * total
                        }
                        .onEnded { value in
                            guard player.duration > 0 else {
                                player.isScrubbing = false
                                return
                            }
                            let x = min(max(value.location.x, 0), geo.size.width)
                            let time = (x / geo.size.width) * total
                            player.progress = time
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

private struct RoutePickerButton: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        container.backgroundColor = .clear

        let picker = AVRoutePickerView(frame: container.bounds)
        picker.tintColor = .systemBlue
        picker.activeTintColor = .systemBlue
        picker.prioritizesVideoDevices = false
        picker.alpha = 0.02
        picker.isUserInteractionEnabled = false
        container.addSubview(picker)
        context.coordinator.picker = picker

        let button = UIButton(type: .system)
        button.frame = container.bounds
        button.setImage(UIImage(systemName: "airplay.audio"), for: .normal)
        button.tintColor = .systemBlue
        button.addTarget(context.coordinator, action: #selector(Coordinator.presentPicker), for: .touchUpInside)
        container.addSubview(button)

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject {
        weak var picker: AVRoutePickerView?

        @objc func presentPicker() {
            guard let button = picker?.subviews.compactMap({ $0 as? UIButton }).first else { return }
            button.sendActions(for: .touchUpInside)
        }
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
