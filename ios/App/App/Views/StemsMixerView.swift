import SwiftUI

/// Exact replica of `.mixer` multitrack console from PULSO Web
struct StemsMixerView: View {
    @ObservedObject var vm: ShowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mixer Toolbar Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 13))
                        .foregroundColor(PulsoTheme.amber)
                    Text("MEZCLADOR DE PISTAS (STEMS)")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.0)
                        .foregroundColor(PulsoTheme.textLight)

                    Text("\(vm.stems.count) STEMS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.amber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PulsoTheme.raise)
                        .cornerRadius(4)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Horizontal rack of stem channels
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.stems) { stem in
                        StemChannelStrip(stem: stem, vm: vm)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulsoTheme.bg.ignoresSafeArea())
    }
}

// MARK: - Individual Stem Channel Strip

struct StemChannelStrip: View {
    let stem: StemItem
    @ObservedObject var vm: ShowViewModel

    var body: some View {
        VStack(spacing: 6) {
            // 1. Channel Title & Color Indicator
            VStack(spacing: 4) {
                Text(stem.label)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(PulsoTheme.textLight)
                    .lineLimit(1)
                    .frame(width: 58)

                Rectangle()
                    .fill(stem.accentColor)
                    .frame(width: 32, height: 2)
            }

            // 2. Bus Switch (FOH vs CUE)
            Button(action: { vm.toggleBus(id: stem.id) }) {
                Text(stem.bus == 0 ? "FOH" : "CUE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(stem.bus == 0 ? PulsoTheme.green : PulsoTheme.teal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PulsoTheme.raise)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(PulsoTheme.border, lineWidth: 1)
                    )
                    .cornerRadius(3)
            }

            // 3. Fader & Peak Meter
            HStack(spacing: 4) {
                // RMS Peak Meter
                VStack(spacing: 0) {
                    Spacer()
                    let meterHeight = max(0, min(140, CGFloat(stem.rms) * 140))
                    Rectangle()
                        .fill(stem.rms > 0.8 ? PulsoTheme.red : (stem.rms > 0.5 ? PulsoTheme.amber : PulsoTheme.green))
                        .frame(width: 4, height: meterHeight)
                }
                .frame(width: 4, height: 140)
                .background(Color.black.opacity(0.5))
                .cornerRadius(2)

                // Vertical Tactile Fader
                VerticalFaderBar(value: Binding(
                    get: { stem.gainDb },
                    set: { vm.setStemDb(id: stem.id, db: $0) }
                ))
                .frame(width: 34, height: 140)
            }

            // 4. Numeric dB Readout
            Text(stem.gainDb <= -59.5 ? "-inf" : String(format: "%.1f dB", stem.gainDb))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PulsoTheme.textDim)

            // 5. Mute & Solo
            HStack(spacing: 4) {
                // Mute
                Button(action: { vm.toggleMute(id: stem.id) }) {
                    Text("M")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(stem.muted ? .white : PulsoTheme.textDim)
                        .frame(width: 24, height: 22)
                        .background(stem.muted ? PulsoTheme.red : PulsoTheme.raise)
                        .cornerRadius(3)
                }

                // Solo
                Button(action: { vm.toggleSolo(id: stem.id) }) {
                    Text("S")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(stem.solo ? Color(hex: 0x111111) : PulsoTheme.textDim)
                        .frame(width: 24, height: 22)
                        .background(stem.solo ? PulsoTheme.amber : PulsoTheme.raise)
                        .cornerRadius(3)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(PulsoTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: PulsoTheme.radSm)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(PulsoTheme.radSm)
    }
}

// MARK: - Vertical Fader Bar with Tactile Thumb & 0 dB mark

struct VerticalFaderBar: View {
    @Binding var value: Float
    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let normalized = max(0, min(1, (value + 60.0) / 70.0))
            let capY = totalHeight * (1.0 - CGFloat(normalized))

            ZStack(alignment: .top) {
                // Slot track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 4, height: totalHeight)
                    .position(x: geo.size.width / 2, y: totalHeight / 2)

                // 0 dB center reference line
                let zeroY = totalHeight * (1.0 - CGFloat(60.0 / 70.0))
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 16, height: 1)
                    .position(x: geo.size.width / 2, y: zeroY)

                // Tactile Fader Cap
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PulsoTheme.raiseHover)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(PulsoTheme.line2, lineWidth: 1)
                        )
                    Rectangle()
                        .fill(PulsoTheme.amber)
                        .frame(height: 2)
                }
                .frame(width: 28, height: 18)
                .position(x: geo.size.width / 2, y: max(9, min(totalHeight - 9, capY)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let locationY = drag.location.y
                        let fraction = 1.0 - (locationY / totalHeight)
                        let clamped = max(0.0, min(1.0, Float(fraction)))
                        value = (clamped * 70.0) - 60.0
                    }
                    .onEnded { drag in
                        if abs(drag.translation.height) < 5 && abs(drag.translation.width) < 5 {
                            let now = Date()
                            if now.timeIntervalSince(lastTapTime) < 0.4 {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    value = 0.0
                                }
                                lastTapTime = .distantPast
                            } else {
                                lastTapTime = now
                            }
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    withAnimation(.easeOut(duration: 0.15)) {
                        value = 0.0
                    }
                }
            )
        }
    }
}

// MARK: - Fader VU Meter View (20 segmented LED bar)

struct FaderVUMeterView: View {
    let level: Float // 0.0 to 1.0
    var isStereo: Bool = false
    var levelR: Float = 0.0

    private let segCount = 20

    var body: some View {
        if isStereo {
            HStack(spacing: 1.5) {
                meterColumn(lvl: level)
                meterColumn(lvl: levelR)
            }
            .padding(1.5)
            .frame(width: 15, height: 120)
            .background(Color(hex: 0x0D0B09))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(PulsoTheme.line2, lineWidth: 0.5)
            )
            .cornerRadius(2)
        } else {
            meterColumn(lvl: level)
                .padding(1.5)
                .frame(width: 8, height: 120)
                .background(Color(hex: 0x0D0B09))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(PulsoTheme.line2, lineWidth: 0.5)
                )
                .cornerRadius(2)
        }
    }

    private func meterColumn(lvl: Float) -> some View {
        VStack(spacing: 1.5) {
            ForEach((0..<segCount).reversed(), id: \.self) { idx in
                let litThreshold = Float(idx) / Float(segCount)
                let isLit = lvl > litThreshold
                let isRed = idx >= segCount - 3
                let litColor = isRed ? PulsoTheme.red : PulsoTheme.amber
                let unlitColor = Color(hex: 0x1A1816)

                RoundedRectangle(cornerRadius: 0.5)
                    .fill(isLit ? litColor : unlitColor)
                    .frame(height: 4)
            }
        }
    }
}
