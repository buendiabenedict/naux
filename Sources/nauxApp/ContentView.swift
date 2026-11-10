import SwiftUI

struct ContentView: View {
    @StateObject private var player = PlayerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                artwork
                trackInfo
                progress
                controls
                volume

                Spacer()
            }
            .padding(24)
            .background(
                LinearGradient(
                    colors: [Color.black, Color.gray.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("naux")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 220)
            Image(systemName: "music.note")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(player.currentTrack.title)
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(.white)
            Text(player.currentTrack.artist)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            Slider(value: $player.progress, in: 0...max(player.duration, 1)) { editing in
                if !editing { player.seek(to: player.progress) }
            }
            .tint(.white)

            HStack {
                Text(format(player.progress))
                Spacer()
                Text(format(player.duration))
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .monospacedDigit()
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
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
    }

    private var volume: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.white.opacity(0.6))
            Slider(value: $player.volume, in: 0...1)
                .tint(.white.opacity(0.8))
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.white.opacity(0.6))
        }
        .font(.caption)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
