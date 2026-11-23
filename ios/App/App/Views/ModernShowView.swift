import SwiftUI

/// Exact replica of `.show-layout-modern` from PULSO Web
struct ModernShowView: View {
    @ObservedObject var vm: ShowViewModel
    @State private var showingTransposeDialog = false
    @State private var showingPadDialog = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                // 1. TOP NAV (.mo-top-nav)
                topNavSection

                // 2. MAIN HERO CARD (.mo-hero-card)
                heroCardSection

                // 3. ARRANGER CAROUSEL (.mo-arranger-carousel)
                arrangerCarouselSection

                // 4. NEXT SONG CARD (.mo-next-card)
                if let next = vm.nextSong {
                    nextSongCard(next)
                }

                // 5. BOTTOM BAR (.mo-bottom-bar)
                bottomBarSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 960)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulsoTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showingTransposeDialog) {
            transposeDialog
        }
        .sheet(isPresented: $showingPadDialog) {
            padDialog
        }
    }

    // MARK: - 1. Top Nav (.mo-top-nav)

    private var topNavSection: some View {
        HStack(spacing: 12) {
            // Prev Button (.mo-nav-btn)
            Button(action: { vm.prevSongAction() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PulsoTheme.textDim)
                    .frame(width: 36, height: 36)
                    .background(PulsoTheme.navBtnBg)
                    .cornerRadius(PulsoTheme.radSm)
            }

            // Center Pill (.mo-nav-center)
            Button(action: { vm.showingSetlistSelectorModal = true }) {
                HStack(spacing: 8) {
                    Text(vm.setlist.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(PulsoTheme.textLight)
                    Text("\(vm.setlist.currentIndex + 1)/\(vm.setlist.songs.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.amber)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(PulsoTheme.mut)
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(PulsoTheme.navBtnBg)
                .cornerRadius(18)
            }

            // Next Button (.mo-nav-btn)
            Button(action: { vm.nextSongAction() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PulsoTheme.textDim)
                    .frame(width: 36, height: 36)
                    .background(PulsoTheme.navBtnBg)
                    .cornerRadius(PulsoTheme.radSm)
            }
        }
    }

    // MARK: - 2. Hero Card (.mo-hero-card)

    private var heroCardSection: some View {
        ZStack(alignment: .bottom) {
            // Card Content (.mo-hero-content)
            VStack(alignment: .leading, spacing: 0) {
                // Top Row (.mo-hc-top)
                HStack(alignment: .top) {
                    // Top Left (.mo-hc-top-left)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vm.currentSong.title.uppercased())
                            .font(.system(size: 20, weight: .heavy))
                            .tracking(2.0)
                            .foregroundColor(PulsoTheme.textLight)
                            .lineLimit(1)

                        Text(vm.currentSong.artist.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(PulsoTheme.textDim)
                            .lineLimit(1)

                        if !vm.currentSong.isDownloadedLocally {
                            Button(action: {
                                vm.verifyAndDownloadStemsIfNeeded(for: vm.currentSong)
                            }) {
                                HStack(spacing: 5) {
                                    if let prog = vm.downloadProgress[vm.currentSong.id] {
                                        ProgressView().tint(PulsoTheme.amber).scaleEffect(0.6)
                                        Text("DESCARGANDO STEMS: \(Int(prog * 100))%")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 10))
                                        Text("STEMS EN SERVIDOR (DESCARGAR)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    }
                                }
                                .foregroundColor(PulsoTheme.amber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(PulsoTheme.amber.opacity(0.15))
                                .cornerRadius(4)
                            }
                        }
                    }

                    Spacer()

                    // Top Right (.mo-hc-top-right)
                    VStack(alignment: .trailing, spacing: 8) {
                        // Key Button (.mo-hc-key)
                        Button(action: { showingTransposeDialog = true }) {
                            Text(vm.currentSong.key)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(PulsoTheme.amber)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: PulsoTheme.radSm)
                                        .stroke(PulsoTheme.border, lineWidth: 1)
                                )
                                .cornerRadius(PulsoTheme.radSm)
                        }

                        // Tempo (.mo-hc-tempo)
                        Text("\(Int(vm.currentSong.bpm)) BPM - \(vm.currentSong.timeSignature)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(PulsoTheme.textDim)
                    }
                }

                Spacer()

                // Bottom Row (.mo-hc-bottom)
                HStack(alignment: .bottom) {
                    // Bottom Left (.mo-hc-bottom-left)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SECCIÓN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(PulsoTheme.textDim)

                        let curSec = vm.currentSong.sections.indices.contains(vm.activeSectionIndex) ?
                            vm.currentSong.sections[vm.activeSectionIndex] : nil
                        Text(curSec?.name ?? "INICIO")
                            .font(.system(size: 48, weight: .black))
                            .foregroundColor(PulsoTheme.textLight)
                            .lineLimit(1)

                        let nextSec = vm.currentSong.sections.indices.contains(vm.activeSectionIndex + 1) ?
                            vm.currentSong.sections[vm.activeSectionIndex + 1] : nil
                        if let n = nextSec {
                            Text("SIGUIENTE: \(n.name)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(PulsoTheme.textLight.opacity(0.8))
                        }
                    }

                    Spacer()

                    // Bottom Right (.mo-hc-bottom-right)
                    VStack(alignment: .trailing, spacing: 10) {
                        let remaining = max(0, vm.currentSong.durationSeconds - vm.currentSeconds)
                        Text(formatCountdown(remaining))
                            .font(.system(size: 48, weight: .black, design: .monospaced))
                            .foregroundColor(PulsoTheme.amber)
                            .lineLimit(1)

                        Text("RESTANTE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(PulsoTheme.textDim)

                        // Loop Button (.mo-hc-loop-btn)
                        Button(action: { vm.toggleLoop() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 11, weight: .bold))
                                Text("LOOP")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            .foregroundColor(vm.loopSection ? Color(hex: 0x17140E) : PulsoTheme.teal)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(vm.loopSection ? PulsoTheme.amber : PulsoTheme.tealDim)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(vm.loopSection ? Color.clear : PulsoTheme.teal.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(20)
                        }
                    }
                }
            }
            .padding(24)

            // Progress Track (.mo-hero-prog-track)
            GeometryReader { geo in
                let pct = vm.currentSong.durationSeconds > 0 ?
                    CGFloat(vm.currentSeconds / vm.currentSong.durationSeconds) : 0
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                    Rectangle()
                        .fill(PulsoTheme.amber)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * pct)))
                }
            }
            .frame(height: 4)
        }
        .frame(height: 280)
        .background(
            ZStack {
                PulsoTheme.cardBg
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: 0x141414).opacity(0.95),
                        Color(hex: 0x28190A).opacity(0.65),
                        Color(hex: 0x141414).opacity(0.95)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: PulsoTheme.radLg)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(PulsoTheme.radLg)
    }

    // MARK: - 3. Arranger Carousel (.mo-arranger-carousel)

    private var arrangerCarouselSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(vm.currentSong.sections) { sec in
                    let isActive = vm.activeSectionIndex == sec.id
                    Button(action: { vm.jumpToSection(index: sec.id) }) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Section Name (.mo-arr-top)
                            Text(sec.name)
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(isActive ? Color(hex: 0x111111) : PulsoTheme.textLight)

                            Spacer()

                            // Waveform Audio Bars (.mo-arr-wave)
                            ArrangerWaveformBars(isActive: isActive)

                            Spacer()

                            // Bar label
                            Text("C.\(sec.startBar)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isActive ? Color(hex: 0x111111).opacity(0.8) : PulsoTheme.textDim)

                            // Accent bottom line
                            Rectangle()
                                .fill(isActive ? Color(hex: 0x111111) : sec.color)
                                .frame(height: 3)
                                .padding(.top, 4)
                        }
                        .padding(10)
                        .frame(width: 100, height: 100)
                        .background(isActive ? PulsoTheme.amber : PulsoTheme.cardBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: PulsoTheme.radMd)
                                .stroke(isActive ? PulsoTheme.amber : PulsoTheme.border, lineWidth: 1)
                        )
                        .cornerRadius(PulsoTheme.radMd)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 4. Next Song Card (.mo-next-card)

    private func nextSongCard(_ song: SongItem) -> some View {
        Button(action: { vm.nextSongAction() }) {
            HStack(spacing: 12) {
                // Next Left (.mo-next-left)
                HStack(spacing: 10) {
                    Text("SIGUIENTE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.0)
                        .foregroundColor(PulsoTheme.textDim)

                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PulsoTheme.raise)
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundColor(PulsoTheme.amber)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(PulsoTheme.textLight)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PulsoTheme.textDim)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Next Right (.mo-next-right)
                HStack(spacing: 8) {
                    Text(song.key)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.amber)
                    Text("›")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(PulsoTheme.textDim)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PulsoTheme.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: PulsoTheme.radMd)
                    .stroke(PulsoTheme.border, lineWidth: 1)
            )
            .cornerRadius(PulsoTheme.radMd)
        }
    }

    // MARK: - 5. Bottom Bar (.mo-bottom-bar)

    private var bottomBarSection: some View {
        HStack(spacing: 16) {
            // Pad Button (.mo-pad-btn)
            Button(action: { showingPadDialog = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13))
                        .foregroundColor(PulsoTheme.amber)

                    Text("PAD · \(vm.padKey)")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(PulsoTheme.textLight)

                    // LED (.mo-pad-led)
                    Circle()
                        .fill(vm.padActive ? PulsoTheme.green : PulsoTheme.dim)
                        .frame(width: 8, height: 8)
                        .shadow(color: vm.padActive ? PulsoTheme.green : Color.clear, radius: 4)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(PulsoTheme.navBtnBg)
                .overlay(
                    RoundedRectangle(cornerRadius: PulsoTheme.radSm)
                        .stroke(PulsoTheme.border, lineWidth: 1)
                )
                .cornerRadius(PulsoTheme.radSm)
            }

            Spacer()

            // Master Control (.mo-master-ctrl)
            HStack(spacing: 12) {
                Text("MASTER")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundColor(PulsoTheme.textDim)

                Slider(value: $vm.masterDb, in: -60...10)
                    .tint(PulsoTheme.amber)
                    .frame(width: 160)

                Text(String(format: "%.1f dB", vm.masterDb))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.textLight)
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(PulsoTheme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: PulsoTheme.radMd)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(PulsoTheme.radMd)
    }

    // MARK: - Modals (Transpose & Pad)

    private var transposeDialog: some View {
        VStack(spacing: 16) {
            Text("TRANSPONER CANCIÓN")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(PulsoTheme.textLight)

            let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(notes, id: \.self) { note in
                    let isSel = vm.currentSong.key == note
                    Button(action: {
                        vm.setSongKey(note)
                        showingTransposeDialog = false
                    }) {
                        Text(note)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(isSel ? Color(hex: 0x111111) : PulsoTheme.textLight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSel ? PulsoTheme.amber : PulsoTheme.panel)
                            .cornerRadius(PulsoTheme.radSm)
                    }
                }
            }

            Text("El tempo se conserva. Click, guía y batería quedan sin transponer.")
                .font(.system(size: 11))
                .foregroundColor(PulsoTheme.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(PulsoTheme.cardBg.ignoresSafeArea())
    }

    private var padDialog: some View {
        VStack(spacing: 16) {
            Text("TONALIDAD DEL PAD")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(PulsoTheme.textLight)

            let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(notes, id: \.self) { note in
                    let isSel = vm.padKey == note
                    Button(action: {
                        vm.padKey = note
                    }) {
                        Text(note)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(isSel ? Color(hex: 0x111111) : PulsoTheme.textLight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSel ? PulsoTheme.amber : PulsoTheme.panel)
                            .cornerRadius(PulsoTheme.radSm)
                    }
                }
            }

            Button(action: {
                vm.togglePad()
                showingPadDialog = false
            }) {
                Text(vm.padActive ? "APAGAR PAD" : "ENCENDER PAD")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(vm.padActive ? .white : Color(hex: 0x111111))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(vm.padActive ? PulsoTheme.red : PulsoTheme.amber)
                    .cornerRadius(PulsoTheme.radSm)
            }
        }
        .padding(24)
        .background(PulsoTheme.cardBg.ignoresSafeArea())
    }

    private func formatCountdown(_ sec: Double) -> String {
        let s = Int(max(0, sec))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Arranger Waveform Audio Bars (.mo-arr-wave)

struct ArrangerWaveformBars: View {
    let isActive: Bool
    let heights: [CGFloat] = [10, 22, 14, 28, 16, 24, 18, 12]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3.5) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? Color(hex: 0x111111).opacity(0.85) : Color.white.opacity(0.85))
                    .frame(width: 3.5, height: heights[i])
            }
        }
        .frame(height: 30)
    }
}
