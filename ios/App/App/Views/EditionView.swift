import SwiftUI

/// Exact replica of `.edition-layout` from PULSO Web (Image 3)
struct EditionView: View {
    @ObservedObject var vm: ShowViewModel

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

            // Add Song Choice Modal (Nube vs Local)
            if vm.showingAddSongModal {
                AddSongChoiceModalView(vm: vm)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulsoTheme.bg.ignoresSafeArea())
    }

    // MARK: - 1. Sidebar (.edition-sidebar)

    private var sidebarSection: some View {
        VStack(spacing: 0) {
            // Sidebar Header (.sidebar-header)
            HStack {
                Button(action: {}) {
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
            // Card Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(PulsoTheme.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: PulsoTheme.green.opacity(0.6), radius: 3)

                    Text(vm.currentSong.title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(PulsoTheme.textLight)

                    Text(vm.currentSong.artist)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PulsoTheme.textDim)

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
                }

                Spacer()

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

                    Button(action: {}) {
                        Text("Guardar")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(Color(hex: 0x060709))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(PulsoTheme.amber)
                            .cornerRadius(5)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PulsoTheme.panel2)

            // Timeline Area (Ocupa todo el espacio disponible)
            VStack(spacing: 0) {
                // Arranger Sections Band (.tl-band de Pulso Web)
                arrangerSectionsBandView
                    .frame(height: 18)
                    .background(Color(hex: 0x1A1714))
                    .border(PulsoTheme.line, width: 0.5)

                // Time Ruler (Bars 1, 5, 9, 13, ...)
                timeRulerView
                    .frame(height: 20)
                    .background(PulsoTheme.blackBox)
                    .border(PulsoTheme.line, width: 0.5)

                // Track Lanes with Waveforms & Playhead (ocupa todo el alto del contenedor)
                GeometryReader { geo in
                    let totalHeight = geo.size.height
                    let count = max(1, vm.stems.count)
                    let spacing: CGFloat = 1.0
                    let availableForRows = totalHeight - (CGFloat(count - 1) * spacing)
                    let rowHeight = max(24.0, availableForRows / CGFloat(count))

                    ZStack(alignment: .leading) {
                        // Tracks ocupando el 100% del alto
                        VStack(spacing: spacing) {
                            ForEach(vm.stems) { stem in
                                TimelineTrackRow(
                                    stem: stem,
                                    isSelected: stem.id == vm.selectedTrackId,
                                    rowHeight: rowHeight
                                )
                                .onTapGesture {
                                    vm.selectTrack(id: stem.id)
                                }
                            }
                        }
                        .frame(width: geo.size.width, height: totalHeight)

                        // Playhead vertical line
                        let pct = vm.currentSong.durationSeconds > 0 ?
                            CGFloat(vm.currentSeconds / vm.currentSong.durationSeconds) : 0
                        let xPos = 64.0 + (geo.size.width - 64.0) * pct

                        Rectangle()
                            .fill(PulsoTheme.amber)
                            .frame(width: 2)
                            .offset(x: xPos)
                            .shadow(color: PulsoTheme.amberGlow, radius: 4, x: 0, y: 0)
                    }
                    .frame(width: geo.size.width, height: totalHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let touchX = value.location.x
                                if touchX >= 64.0 {
                                    let trackW = max(1.0, geo.size.width - 64.0)
                                    let ratio = max(0.0, min(1.0, Double((touchX - 64.0) / trackW)))
                                    vm.seek(to: ratio * vm.currentSong.durationSeconds)
                                }
                            }
                    )
                }
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
        GeometryReader { geo in
            let totalBars: CGFloat = 96.0
            let bandWidth = geo.size.width

            ZStack(alignment: .leading) {
                ForEach(vm.currentSong.sections) { sec in
                    let leftPct = CGFloat(sec.startBar - 1) / totalBars
                    let widthPct = CGFloat(sec.lengthBars) / totalBars
                    let xPos = leftPct * bandWidth
                    let secWidth = max(24.0, widthPct * bandWidth)

                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sec.color.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(sec.color.opacity(0.8), lineWidth: 1)
                            )

                        Text(sec.name)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(sec.color)
                            .lineLimit(1)
                            .padding(.horizontal, 2)
                    }
                    .frame(width: secWidth, height: 16)
                    .offset(x: xPos)
                    .onTapGesture {
                        if let idx = vm.currentSong.sections.firstIndex(where: { $0.id == sec.id }) {
                            vm.jumpToSection(index: idx)
                        }
                    }
                }
            }
            .frame(width: bandWidth, height: geo.size.height)
        }
    }

    private var timeRulerView: some View {
        HStack(spacing: 0) {
            // Track label placeholder offset
            Text("")
                .frame(width: 64)

            // Numbered bar grid
            HStack(spacing: 0) {
                ForEach([1, 5, 9, 13, 17, 21, 25, 29, 33, 37, 41, 45, 49, 53, 57, 61, 65, 69, 73, 77, 81, 85, 89, 93], id: \.self) { bar in
                    HStack(spacing: 2) {
                        Text("\(bar)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.amber)
                        Rectangle()
                            .fill(PulsoTheme.line2)
                            .frame(width: 1, height: 6)
                        Spacer()
                    }
                }
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
                    HStack(spacing: 8) {
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
    var rowHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            // Track Name
            Text(stem.label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(isSelected ? PulsoTheme.amber : PulsoTheme.ink2)
                .frame(width: 64, alignment: .leading)
                .padding(.leading, 8)

            // Monochrome Gray Waveform representation (fills entire lane)
            ZStack {
                // Background of lane
                Color.black.opacity(0.4)

                // Continuous horizontal center baseline
                Rectangle()
                    .fill(Color(hex: 0x8C9298).opacity(0.35))
                    .frame(height: 1)

                // Monochrome Gray Waveform bars/envelope filling full lane
                WaveformLaneShape(stemId: stem.id)
                    .stroke(Color(hex: 0x8C9298), lineWidth: 1)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(PulsoTheme.line.opacity(0.4), width: 0.5)
        }
        .frame(height: rowHeight)
        .background(isSelected ? PulsoTheme.amber.opacity(0.08) : Color.clear)
    }
}

// MARK: - Waveform Lane Shape (Mathematical Envelope Generator)

struct WaveformLaneShape: Shape {
    let stemId: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 2.5
        let midY = rect.midY

        for x in stride(from: 0, to: rect.width, by: step) {
            let ratio = Double(x / rect.width)
            let baseEnv: Double
            if stemId == "click" {
                // Sharp periodic spikes
                baseEnv = (Int(x) % 24 < 3) ? 0.85 : 0.04
            } else if stemId == "drums" || stemId == "bass" {
                // Dense rhythmic waveforms
                baseEnv = 0.25 + 0.70 * abs(sin(ratio * 70.0) * cos(ratio * 35.0))
            } else if stemId == "guide" {
                // Sparse vocal cues
                baseEnv = (sin(ratio * 18.0) > 0.35) ? 0.75 : 0.04
            } else {
                // Melodic instruments
                baseEnv = 0.18 + 0.65 * abs(sin(ratio * 40.0))
            }

            let amp = CGFloat(baseEnv) * max(2.0, (rect.height / 2.0 - 2.0))
            path.move(to: CGPoint(x: x, y: midY - amp))
            path.addLine(to: CGPoint(x: x, y: midY + amp))
        }

        return path
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

                // Medidor VU de audio por pista
                FaderVUMeterView(level: stem.rms)

                // Vertical Tactile Fader
                VerticalFaderBar(value: Binding(
                    get: { stem.gainDb },
                    set: { vm.setStemDb(id: stem.id, db: $0) }
                ))
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

                // Medidor Estéreo L/R Master
                FaderVUMeterView(level: vm.masterRmsL, isStereo: true, levelR: vm.masterRmsR)

                VerticalFaderBar(value: $vm.masterDb)
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
