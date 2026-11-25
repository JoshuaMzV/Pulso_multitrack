import SwiftUI
import Combine

/// Exact replica of `.edition-layout` from PULSO Web (Image 3)
struct EditionView: View {
    @ObservedObject var vm: ShowViewModel
    @State private var scrub = TimelineScrub()

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // 1. LEFT SIDEBAR (.edition-sidebar)
                sidebarSection
                    .frame(width: 250)
                    .background(PulsoTheme.panel2)
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(PulsoTheme.line),
                        alignment: .trailing
                    )

                // 2. MAIN WORKSPACE (.edition-main)
                VStack(spacing: 12) {
                    // UPPER CARD: MULTITRACK TIMELINE (.console-timeline-card)
                    multitrackTimelineCard

                    // LOWER CARD: STEMS MIXER RACK (.console-mixer-card)
                    editionMixerCard
                }
                .padding(12)
                .background(PulsoTheme.bg)
            }

            // Arranger Dropdown Panel
            if vm.showingArrangerPanel {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { vm.showingArrangerPanel = false }

                ArrangerSubmenuPanel(vm: vm)
                    .transition(.scale.combined(with: .opacity))
            }

            // Transpose Dialog
            if vm.showingTransposeDialog {
                TransposeDialogView(vm: vm, isPresented: $vm.showingTransposeDialog)
                    .transition(.opacity)
            }


        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulsoTheme.bg.ignoresSafeArea())
        .onDisappear { scrub.seconds = nil }
        .onChange(of: vm.currentSong.id) { _ in scrub.seconds = nil }
    }

    // MARK: - 1. Sidebar (.edition-sidebar)

    private var sidebarSection: some View {
        VStack(spacing: 0) {
            // Sidebar Header (.sidebar-header)
            HStack {
                Button(action: { vm.showingSetlistSelectorModal = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(PulsoTheme.ink2)
                        Text(vm.setlist.name)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(PulsoTheme.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                    }
                }

                Spacer()

                // + Button opens Nube vs Local Choice Modal
                Button(action: { vm.showingAddSongModal = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(PulsoTheme.ink2)
                        .frame(width: 26, height: 26)
                        .background(PulsoTheme.raise)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .border(PulsoTheme.line, width: 1)

            // Songs List with Reordering and Inter-song Transitions
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(Array(vm.setlist.songs.enumerated()), id: \.element.id) { index, song in
                        let isActive = song.id == vm.currentSong.id

                        // Song Card
                        Button(action: { vm.loadSong(song) }) {
                            VStack(spacing: 6) {
                                // Top row: Title & Key badge (No arrows)
                                HStack(spacing: 6) {
                                    // Indicador circular de estado de descarga (check verde cuando está lista)
                                    if vm.isSongDownloaded(song) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(PulsoTheme.green)
                                    } else if let prog = vm.downloadProgress[song.id] {
                                        ZStack {
                                            Circle()
                                                .stroke(PulsoTheme.border, lineWidth: 1.5)
                                                .frame(width: 11, height: 11)
                                            Circle()
                                                .trim(from: 0, to: CGFloat(prog))
                                                .stroke(PulsoTheme.amber, lineWidth: 1.5)
                                                .frame(width: 11, height: 11)
                                                .rotationEffect(.degrees(-90))
                                        }
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 11))
                                            .foregroundColor(PulsoTheme.dim)
                                    }

                                    Text("\(index + 1). \(song.title)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(isActive ? PulsoTheme.ink : PulsoTheme.textLight)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(song.key)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(isActive ? PulsoTheme.amber : PulsoTheme.textDim)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(PulsoTheme.line2, lineWidth: 1)
                                        )
                                        .cornerRadius(3)
                                }

                                // Bottom row: BPM, Time signature, Delete
                                HStack(spacing: 6) {
                                    Text("\(Int(song.bpm)) BPM \(song.timeSignature)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(PulsoTheme.textDim)

                                    Spacer()

                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(PulsoTheme.dim)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isActive ? PulsoTheme.amber.opacity(0.08) : PulsoTheme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isActive ? PulsoTheme.amber : PulsoTheme.border, lineWidth: 1)
                            )
                            .cornerRadius(8)
                        }

                        // Inter-song Transition Connector (.sc-transition)
                        if index < vm.setlist.songs.count - 1 {
                            HStack(spacing: 6) {
                                Rectangle().fill(PulsoTheme.line).frame(height: 1)

                                Button(action: {
                                    vm.cycleTransition(for: song.id)
                                }) {
                                    HStack(spacing: 4) {
                                        Text(song.transition.icon)
                                            .font(.system(size: 11, weight: .bold))
                                        Text(song.transition.label)
                                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                    }
                                    .foregroundColor(PulsoTheme.amber)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(PulsoTheme.raise)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(PulsoTheme.line2, lineWidth: 1)
                                    )
                                    .cornerRadius(12)
                                }

                                Rectangle().fill(PulsoTheme.line).frame(height: 1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(10)
            }

            Spacer()

            // User Dropdown Menu Popover
            if vm.showingUserDropdown {
                UserDropdownView(vm: vm)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }

            // Sidebar Account Slot (.sidebar-account-slot)
            Button(action: {
                withAnimation {
                    vm.showingUserDropdown.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    // Avatar
                    Text(vm.currentUser.avatar)
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(Color(hex: 0x111111))
                        .frame(width: 28, height: 28)
                        .background(PulsoTheme.amber)
                        .cornerRadius(14)

                    Text("@\(vm.currentUser.username)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PulsoTheme.ink2)
                        .lineLimit(1)

                    Spacer()

                    Text(vm.currentUser.role.rawValue)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PulsoTheme.purple)
                        .cornerRadius(4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PulsoTheme.panel)
                .border(PulsoTheme.line, width: 1)
            }
        }
    }

    // MARK: - 2. Multitrack Timeline Card (.console-timeline-card)

    private var multitrackTimelineCard: some View {
        VStack(spacing: 0) {
            // Card Header (con protección de overflow para Danzaré y títulos largos)
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(vm.currentSong.title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(PulsoTheme.textLight)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(vm.currentSong.artist)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PulsoTheme.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Song Key Button in Edition view
                    Button(action: { vm.showingTransposeDialog = true }) {
                        Text(vm.currentSong.key)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.amber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(PulsoTheme.line2, lineWidth: 1)
                            )
                            .cornerRadius(4)
                    }

                    // Estado de descarga de stems
                    if !vm.isSongDownloaded(vm.currentSong) {
                        Button(action: {
                            vm.verifyAndDownloadStemsIfNeeded(for: vm.currentSong)
                        }) {
                            HStack(spacing: 5) {
                                if let prog = vm.downloadProgress[vm.currentSong.id] {
                                    ProgressView().tint(PulsoTheme.amber).scaleEffect(0.6)
                                    Text("\(Int(prog * 100))%")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                } else {
                                    Image(systemName: "icloud.and.arrow.down.fill")
                                        .font(.system(size: 10))
                                    Text("DESCARGAR STEMS")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                }
                            }
                            .foregroundColor(PulsoTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PulsoTheme.amber.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    // ARRANGER Submenu Toggle Button
                    Button(action: {
                        withAnimation {
                            vm.showingArrangerPanel.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.split.2x2")
                                .font(.system(size: 11))
                            Text("ARRANGER")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(vm.showingArrangerPanel ? Color(hex: 0x060709) : PulsoTheme.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(vm.showingArrangerPanel ? PulsoTheme.amber : PulsoTheme.raise)
                        .cornerRadius(5)
                    }

                    Button(action: {
                        Task { await vm.saveSetlistsToBackend() }
                    }) {
                        HStack(spacing: 5) {
                            if vm.isSavingSetlist {
                                ProgressView().tint(.black).scaleEffect(0.7)
                            } else if vm.setlistSavedSuccess {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(vm.setlistSavedSuccess ? "¡Guardado!" : (vm.isSavingSetlist ? "Guardando..." : "Guardar"))
                                .font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundColor(Color(hex: 0x060709))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(vm.setlistSavedSuccess ? PulsoTheme.green : PulsoTheme.amber)
                        .cornerRadius(5)
                    }
                    .disabled(vm.isSavingSetlist)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PulsoTheme.panel2)

            // Timeline Area
            VStack(spacing: 0) {
                // Arranger Sections Band (.tl-band de Pulso Web)
                arrangerSectionsBandView
                    .frame(height: 26)
                    .background(Color(hex: 0x1A1714))
                    .border(PulsoTheme.line, width: 0.5)

                // Time Ruler (Bars 1, 5, 9, 13, ...)
                timeRulerView
                    .frame(height: 22)
                    .background(PulsoTheme.blackBox)
                    .border(PulsoTheme.line, width: 0.5)

                // Track Lanes con Scroll Vertical + Playhead aislado de 60-120 FPS
                TimelineTracksContainer(
                    stems: vm.stems,
                    selectedTrackId: vm.selectedTrackId,
                    duration: vm.currentSong.durationSeconds,
                    isPlaying: vm.isPlaying,
                    position: { vm.currentSeconds },
                    pausedSeconds: vm.isPlaying ? nil : vm.currentSeconds,
                    scrub: scrub,
                    audio: .shared,
                    onSelectTrack: { id in vm.selectTrack(id: id) },
                    onSeek: { sec in vm.seek(to: sec) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PulsoTheme.panel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulsoTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: PulsoTheme.radMd)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(PulsoTheme.radMd)
    }

    private var arrangerSectionsBandView: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 64)

            GeometryReader { geo in
                let bandWidth = geo.size.width
                let totBars = CGFloat(vm.timelineBarSpan)

                ZStack(alignment: .leading) {
                    ForEach(vm.currentSong.sections) { sec in
                        let xPos = (CGFloat(max(0, sec.startBar - 1)) / totBars) * bandWidth
                        let secWidth = max(0.0, (CGFloat(sec.lengthBars) / totBars) * bandWidth)
                        let isSelected = vm.activeSectionIndex == sec.id

                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(sec.color.opacity(0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isSelected ? Color.white : sec.color.opacity(0.8), lineWidth: isSelected ? 1.5 : 1)
                                )

                            if secWidth > 48 {
                                Text(sec.name)
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundColor(sec.color)
                                    .lineLimit(1)
                            } else {
                                Text(sec.shortName)
                                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                    .foregroundColor(sec.color)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: secWidth, height: 22)
                        .offset(x: xPos)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let idx = vm.currentSong.sections.firstIndex(where: { $0.id == sec.id }) {
                                vm.jumpToSection(index: idx)
                            }
                        }
                    }
                }
            }
        }
    }

    private var timeRulerView: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 64)

            GeometryReader { geo in
                let bandWidth = geo.size.width
                let totBars = CGFloat(vm.timelineBarSpan)
                let barWidth = bandWidth / totBars

                Canvas { context, size in
                    let totalB = Int(ceil(totBars))
                    for barIndex in 0..<totalB {
                        let x = CGFloat(barIndex) * barWidth
                        let isMajor = (barIndex % 4 == 0) // Compás 1, 5, 9, 13...

                        var linePath = Path()
                        if isMajor {
                            linePath.move(to: CGPoint(x: x, y: 0))
                            linePath.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(linePath, with: .color(PulsoTheme.amber.opacity(0.7)), lineWidth: 1.0)

                            let barNum = barIndex + 1
                            let text = Text("\(barNum)")
                                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                                .foregroundColor(PulsoTheme.amber)
                            context.draw(context.resolve(text), at: CGPoint(x: x + 4, y: size.height / 2.0), anchor: .leading)
                        } else {
                            linePath.move(to: CGPoint(x: x, y: size.height - 6))
                            linePath.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(linePath, with: .color(PulsoTheme.line2), lineWidth: 0.8)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let ratio = max(0.0, min(1.0, Double(location.x / max(1.0, bandWidth))))
                    vm.seek(to: ratio * vm.currentSong.durationSeconds)
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            let ratio = max(0.0, min(1.0, Double(value.location.x / max(1.0, bandWidth))))
                            scrub.seconds = ratio * vm.currentSong.durationSeconds
                        }
                        .onEnded { value in
                            if let target = scrub.seconds {
                                vm.seek(to: target)
                                scrub.seconds = nil
                            }
                        }
                )
            }
        }
    }

    // MARK: - 3. Stems Mixer Rack (.console-mixer-card)

    private var editionMixerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mixer Toolbar
            HStack(spacing: 8) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 12))
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

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Horizontal rack of mixer channels with STICKY Master overlay (traspasa y flota encima como en navegador)
            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(vm.stems) { stem in
                            EditionMixerChannelStrip(
                                stem: stem,
                                isSelected: stem.id == vm.selectedTrackId,
                                vm: vm
                            )
                            .onTapGesture {
                                vm.selectTrack(id: stem.id)
                            }
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 96) // Espacio para que el último stem no quede tapado por Master
                    .padding(.bottom, 10)
                }

                // Canal Master flotante sticky a la derecha
                HStack(spacing: 0) {
                    // Sombra degradada para difuminar los stems que pasan por debajo
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.6),
                            PulsoTheme.cardBg
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 18)

                    MasterMixerChannelStrip(vm: vm)
                        .padding(.trailing, 10)
                }
                .padding(.bottom, 10)
            }
        }
        .background(PulsoTheme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: PulsoTheme.radMd)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(PulsoTheme.radMd)
    }
}

// MARK: - Individual Track Row in Timeline

struct TimelineTrackRow: View {
    let stem: StemItem
    let isSelected: Bool
    var rowHeight: CGFloat = 42
    var peaks: [Float] = []
    var onSelect: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            // Track Name (al pulsar selecciona el track para el mezclador)
            Text(stem.label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(isSelected ? PulsoTheme.amber : PulsoTheme.ink2)
                .padding(.leading, 8)
                .frame(width: 64, height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                }

            // Monochrome Gray Waveform representation (fills entire lane)
            ZStack {
                // Background of lane
                Color.black.opacity(0.4)

                // Real audio waveform or flat line for silence
                RealWaveformLaneView(peaks: peaks)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(PulsoTheme.line.opacity(0.4), width: 0.5)
        }
        .frame(height: rowHeight)
        .background(isSelected ? PulsoTheme.amber.opacity(0.08) : Color.clear)
    }
}

// MARK: - Real PCM Waveform Lane View

struct RealWaveformLaneView: View {
    let peaks: [Float]

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2.0
            let maxH = max(2.0, (size.height / 2.0) - 2.0)

            // Línea central de referencia base
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: midY))
            baseline.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(baseline, with: .color(Color(hex: 0x8C9298).opacity(0.35)), lineWidth: 1.0)

            guard !peaks.isEmpty else { return }

            let count = peaks.count
            let step = size.width / CGFloat(count)

            var wavePath = Path()
            for (idx, peak) in peaks.enumerated() {
                let x = CGFloat(idx) * step
                if peak > 0.02 {
                    let amp = CGFloat(peak) * maxH
                    wavePath.move(to: CGPoint(x: x, y: midY - amp))
                    wavePath.addLine(to: CGPoint(x: x, y: midY + amp))
                }
            }
            context.stroke(wavePath, with: .color(Color(hex: 0x8C9298)), lineWidth: 1.0)
        }
    }
}

// MARK: - Edition Mixer Channel Strip (Image 3)

struct EditionMixerChannelStrip: View {
    let stem: StemItem
    let isSelected: Bool
    @ObservedObject var vm: ShowViewModel

    var body: some View {
        VStack(spacing: 5) {
            // Track Label
            Text(stem.label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(isSelected ? PulsoTheme.amber : PulsoTheme.textLight)
                .lineLimit(1)
                .frame(width: 58)

            // EQ Button (No aparece en CLICK y GUIDE)
            if stem.id == "click" || stem.id == "guide" {
                Color.clear
                    .frame(width: 34, height: 18)
            } else {
                Button(action: {}) {
                    Text("EQ")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(PulsoTheme.ink2)
                        .frame(width: 34, height: 18)
                        .background(PulsoTheme.raise)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(PulsoTheme.line2, lineWidth: 1)
                        )
                        .cornerRadius(3)
                }
            }

            // Fader with Scale Markings (+10, 0, -60) + Medidor VU
            HStack(spacing: 3) {
                // Scale markings
                VStack {
                    Text("+10")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.dim)
                    Spacer()
                    Text("0")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.amber)
                    Spacer()
                    Text("-60")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.dim)
                }
                .frame(height: 120)

                // Medidor VU de audio por pista (aislado en TimelineView GPU a 30fps)
                LiveStemVUMeterView(stemId: stem.id, isPlaying: vm.isPlaying)

                // Vertical Tactile Fader
                VerticalFaderBar(
                    value: Binding(
                        get: { stem.gainDb },
                        set: { vm.setStemDb(id: stem.id, db: $0) }
                    ),
                    onDragUpdate: { newDb in
                        let anySolo = vm.stems.contains(where: { $0.solo })
                        MultitrackAudioEngine.shared.updateVolumeDirect(stemId: stem.id, gainDb: newDb, muted: stem.muted, solo: stem.solo, anySolo: anySolo)
                    },
                    onDragEnd: { finalDb in
                        vm.setStemDb(id: stem.id, db: finalDb)
                    }
                )
                .frame(width: 28, height: 120)
            }

            // Mute & Solo (Click solo tiene Mute)
            HStack(spacing: 4) {
                Button(action: { vm.toggleMute(id: stem.id) }) {
                    Text("M")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(stem.muted ? .white : PulsoTheme.textDim)
                        .frame(width: 22, height: 18)
                        .background(stem.muted ? PulsoTheme.red : PulsoTheme.raise)
                        .cornerRadius(3)
                }

                if stem.id == "click" {
                    Color.clear
                        .frame(width: 22, height: 18)
                } else {
                    Button(action: { vm.toggleSolo(id: stem.id) }) {
                        Text("S")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(stem.solo ? Color(hex: 0x111111) : PulsoTheme.textDim)
                            .frame(width: 22, height: 18)
                            .background(stem.solo ? PulsoTheme.amber : PulsoTheme.raise)
                            .cornerRadius(3)
                    }
                }
            }

            // Numeric dB Readout
            Text(stem.gainDb <= -59.5 ? "-inf" : String(format: "%.1f dB", stem.gainDb))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? PulsoTheme.amber : PulsoTheme.ink2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(PulsoTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: PulsoTheme.radSm)
                .stroke(isSelected ? PulsoTheme.amber : PulsoTheme.border, lineWidth: isSelected ? 2 : 1)
        )
        .cornerRadius(PulsoTheme.radSm)
    }
}

// MARK: - Master Channel Strip in Edition View

struct MasterMixerChannelStrip: View {
    @ObservedObject var vm: ShowViewModel

    var body: some View {
        VStack(spacing: 5) {
            // Title
            Text("MASTER")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(PulsoTheme.amber)
                .lineLimit(1)
                .frame(width: 58)

            // EQ Button
            Button(action: {}) {
                Text("EQ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(PulsoTheme.ink2)
                    .frame(width: 34, height: 18)
                    .background(PulsoTheme.raise)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(PulsoTheme.line2, lineWidth: 1)
                    )
                    .cornerRadius(3)
            }

            // Fader with Scale Markings + Medidor Estéreo Master (L y R)
            HStack(spacing: 3) {
                VStack {
                    Text("+10")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.dim)
                    Spacer()
                    Text("0")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.amber)
                    Spacer()
                    Text("-60")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.dim)
                }
                .frame(height: 120)

                // Medidor Estéreo L/R Master aislado en TimelineView GPU
                LiveMasterVUMeterView(isPlaying: vm.isPlaying)

                VerticalFaderBar(
                    value: $vm.masterDb,
                    onDragUpdate: { newDb in
                        MultitrackAudioEngine.shared.setMasterDb(newDb)
                    },
                    onDragEnd: { finalDb in
                        vm.masterDb = finalDb
                    }
                )
                .frame(width: 28, height: 120)
            }

            // Mute Button
            Button(action: {}) {
                Text("M")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(PulsoTheme.textDim)
                    .frame(width: 44, height: 18)
                    .background(PulsoTheme.raise)
                    .cornerRadius(3)
            }

            // Numeric dB Readout
            Text(String(format: "%.1f dB", vm.masterDb))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PulsoTheme.amber)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(PulsoTheme.panel2)
        .overlay(
            RoundedRectangle(cornerRadius: PulsoTheme.radSm)
                .stroke(PulsoTheme.line2, lineWidth: 1)
        )
        .cornerRadius(PulsoTheme.radSm)
    }
}

// MARK: - Hardware-Accelerated Isolated Playhead & Track Scroll Container

struct TimelineTracksContainer: View {
    let stems: [StemItem]
    let selectedTrackId: String
    let duration: Double
    let isPlaying: Bool
    let position: () -> Double
    let pausedSeconds: Double?
    let scrub: TimelineScrub
    @ObservedObject var audio: MultitrackAudioEngine
    let onSelectTrack: (String) -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(1.0, geo.size.width - 64.0)
            let trackRowHeight: CGFloat = 42.0

            ZStack(alignment: .leading) {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 1.0) {
                        ForEach(stems) { stem in
                            TimelineTrackRow(
                                stem: stem,
                                isSelected: stem.id == selectedTrackId,
                                rowHeight: trackRowHeight,
                                peaks: audio.waveformPeaks[stem.id] ?? [],
                                onSelect: { onSelectTrack(stem.id) }
                            )
                        }
                    }
                    .frame(width: geo.size.width)
                }

                LivePlayheadView(
                    isPlaying: isPlaying,
                    duration: duration,
                    trackWidth: trackWidth,
                    position: position,
                    pausedSeconds: pausedSeconds,
                    scrub: scrub
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                if location.x >= 64.0 {
                    let ratio = max(0.0, min(1.0, Double((location.x - 64.0) / trackWidth)))
                    onSeek(ratio * duration)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            let touchX = value.location.x
                            if touchX >= 64.0 {
                                let ratio = max(0.0, min(1.0, Double((touchX - 64.0) / trackWidth)))
                                scrub.seconds = ratio * duration
                            }
                        }
                    }
                    .onEnded { _ in
                        if let target = scrub.seconds {
                            onSeek(target)
                            scrub.seconds = nil
                        }
                    }
            )
        }
    }
}

/// Solo el cursor observa la posición provisional del gesto.
final class TimelineScrub: ObservableObject {
    @Published var seconds: Double?
}

struct LivePlayheadView: View {
    let isPlaying: Bool
    let duration: Double
    let trackWidth: CGFloat
    let position: () -> Double
    let pausedSeconds: Double?
    @ObservedObject var scrub: TimelineScrub

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying || scrub.seconds != nil)) { _ in
            let sec: Double = {
                if let scrub = scrub.seconds { return scrub }
                return pausedSeconds ?? position()
            }()
            let dur = max(1.0, duration)
            let pct = CGFloat(max(0.0, min(1.0, sec / dur)))
            let xPos = 64.0 + trackWidth * pct

            Rectangle()
                .fill(PulsoTheme.amber)
                .frame(width: 2)
                .offset(x: xPos)
                .shadow(color: PulsoTheme.amberGlow, radius: 4, x: 0, y: 0)
                .allowsHitTesting(false)
        }
    }
}

/// Un solo muestreo del mezclador para todos los medidores visibles.
@MainActor
private enum MeterUpdates {
    static let frames = Timer.publish(every: 0.10, on: .main, in: .common)
        .autoconnect()
        .map { _ in MultitrackAudioEngine.shared.meterSnapshot() }
        .share()
}

struct LiveStemVUMeterView: View {
    let stemId: String
    let isPlaying: Bool

    var body: some View {
        LiveMeter(stemId: stemId, isPlaying: isPlaying)
    }
}

struct LiveMasterVUMeterView: View {
    let isPlaying: Bool

    var body: some View {
        LiveMeter(stemId: nil, isPlaying: isPlaying)
    }
}

private struct LiveMeter: View {
    let stemId: String?
    let isPlaying: Bool
    @State private var band = 0
    @State private var clipUntil = Date.distantPast

    var body: some View {
        let colors: [Color] = [.secondary.opacity(0.25), .green.opacity(0.5), .green, .red]
        let labels = ["Silencio", "Bajo", "Señal", "Saturación"]
        let index = isPlaying ? band : 0
        let light = Capsule().fill(colors[index])
            .frame(width: 6, height: 18)
            .frame(height: 120, alignment: .center)
            .accessibilityLabel("Nivel de audio")
            .accessibilityValue(labels[index])
        if isPlaying {
            light.onReceive(MeterUpdates.frames) { peaks in
                let peak = peaks[stemId] ?? 0
                if peak >= 1 { clipUntil = Date().addingTimeInterval(0.6) }
                let next = Date() < clipUntil ? 3 : peak >= 0.1 ? 2 : peak >= 0.001 ? 1 : 0
                if band != next { band = next }
            }
            .onDisappear { band = 0; clipUntil = .distantPast }
        } else {
            light
        }
    }
}
