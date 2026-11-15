import SwiftUI

/// Exact replica of `.app-header` from PULSO Web
struct AppHeaderView: View {
    @ObservedObject var vm: ShowViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Transport Cluster
            HStack(spacing: 8) {
                // Play / Pause Button (.hdr-play-btn)
                Button(action: { vm.togglePlayPause() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(PulsoTheme.amber)
                            .shadow(color: PulsoTheme.amberGlow, radius: 5, x: 0, y: 0)
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(Color(hex: 0x060709))
                    }
                    .frame(width: 36, height: 33)
                }

                // Stop Button (.hdr-stop-btn)
                Button(action: { vm.stop() }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(PulsoTheme.raise)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(PulsoTheme.line2, lineWidth: 1)
                            )
                        Image(systemName: "square.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PulsoTheme.ink)
                    }
                    .frame(width: 31, height: 33)
                }

                // Time Box (.hdr-time-box)
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatTime(vm.currentSeconds))
                        .font(.system(size: 13.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(formatTime(vm.currentSeconds)) / \(formatTime(vm.currentSong.durationSeconds))")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.amber)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(minWidth: 80, height: 33)
                .background(PulsoTheme.blackBox)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(PulsoTheme.line, lineWidth: 1)
                )
                .cornerRadius(6)

                // Bar Box (.hdr-bar-box)
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMPÁS \(vm.currentBar).\(vm.currentBeat)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.ink)
                        .lineLimit(1)

                    // 4 Beat Dots (.beat-dots)
                    HStack(spacing: 4) {
                        ForEach(1...4, id: \.self) { beat in
                            Circle()
                                .fill(vm.currentBeat == beat ?
                                      (beat == 1 ? PulsoTheme.amber : PulsoTheme.green) :
                                      PulsoTheme.dim)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(minWidth: 86, height: 33)
                .background(PulsoTheme.blackBox)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(PulsoTheme.line, lineWidth: 1)
                )
                .cornerRadius(6)
            }

            Spacer()

            // View Hub (.view-hub)
            HStack(spacing: 2) {
                // EDICIÓN
                Button(action: { vm.mode = .edition }) {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                        Text("EDICIÓN")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundColor(vm.mode == .edition ? PulsoTheme.amber : PulsoTheme.mut)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(vm.mode == .edition ? PulsoTheme.panel : Color.clear)
                    .cornerRadius(6)
                }

                // SHOW
                Button(action: { vm.mode = .show }) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text("SHOW")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundColor(vm.mode == .show ? PulsoTheme.amber : PulsoTheme.mut)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(vm.mode == .show ? PulsoTheme.panel : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(vm.mode == .show ? PulsoTheme.line2 : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
            }
            .padding(2)
            .background(PulsoTheme.raise)
            .cornerRadius(8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(height: 48)
        .background(PulsoTheme.panel2)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(PulsoTheme.line),
            alignment: .bottom
        )
    }

    private func formatTime(_ sec: Double) -> String {
        let s = Int(max(0, sec))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
