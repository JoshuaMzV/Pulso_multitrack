import SwiftUI

/// Panel completo de administración y creación de secciones de Arranger
struct ArrangerSubmenuPanel: View {
    @ObservedObject var vm: ShowViewModel
    @State private var customSectionName: String = ""
    @State private var selectedBars: Int = 8
    @State private var insertAtCurrentBar: Bool = false

    let defaultLabels: [(name: String, colorHex: String)] = [
        ("INTRO", "#3B82F6"),
        ("VERSO", "#14B8A6"),
        ("PRECORO", "#F59E0B"),
        ("CORO", "#EF4444"),
        ("PUENTE", "#8B5CF6"),
        ("INSTRUMENTAL", "#EC4899"),
        ("INTERLUDIO", "#6366F1"),
        ("SOLO", "#F97316"),
        ("FINAL", "#6B7280")
    ]

    var nextEndBar: Int {
        vm.currentSong.sections.map { $0.startBar + $0.lengthBars }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.split.2x2")
                        .font(.system(size: 13))
                        .foregroundColor(PulsoTheme.amber)
                    Text("GESTIÓN DE ARRANGER")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(PulsoTheme.ink)
                }

                Spacer()

                Button(action: { vm.showingArrangerPanel = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PulsoTheme.mut)
                        .frame(width: 24, height: 24)
                        .background(PulsoTheme.raise)
                        .cornerRadius(12)
                }
            }

            // Configuración de inserción (Duración y Posición)
            HStack(spacing: 8) {
                // Selector de compases
                HStack(spacing: 4) {
                    ForEach([4, 8, 12, 16], id: \.self) { bars in
                        Button(action: { selectedBars = bars }) {
                            Text("\(bars)c")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(selectedBars == bars ? Color(hex: 0x060709) : PulsoTheme.ink2)
                                .frame(width: 32, height: 24)
                                .background(selectedBars == bars ? PulsoTheme.amber : PulsoTheme.raise)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                // Botón de alternar posición
                Button(action: { insertAtCurrentBar.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: insertAtCurrentBar ? "pin.fill" : "arrow.right.to.line")
                            .font(.system(size: 9))
                        ArrangerPositionLabel(position: vm.musicalPosition, atCursor: insertAtCurrentBar, endBar: nextEndBar)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(PulsoTheme.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PulsoTheme.amber.opacity(0.12))
                    .cornerRadius(4)
                }
            }

            Text("Toca una sección para agregarla:")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(PulsoTheme.mut)

            // Grid de Botones de Secciones
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(defaultLabels, id: \.name) { item in
                    Button(action: {
                        let targetBar = insertAtCurrentBar ? vm.currentBar : nextEndBar
                        vm.addSection(name: item.name, colorHex: item.colorHex, startBar: targetBar, lengthBars: selectedBars)
                    }) {
                        Text(item.name)
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(PulsoTheme.raise)
                            .overlay(
                                Rectangle()
                                    .fill(Color(hexString: item.colorHex))
                                    .frame(height: 2.5),
                                alignment: .bottom
                            )
                            .cornerRadius(4)
                    }
                }
            }

            // Sección personalizada (+ OTRO)
            HStack(spacing: 6) {
                TextField("Nombre sección...", text: $customSectionName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(PulsoTheme.raise)
                    .cornerRadius(4)

                Button(action: {
                    let trimmed = customSectionName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let targetBar = insertAtCurrentBar ? vm.currentBar : nextEndBar
                    vm.addSection(name: trimmed.uppercased(), colorHex: "#14B8A6", startBar: targetBar, lengthBars: selectedBars)
                    customSectionName = ""
                }) {
                    Text("+ AGREGAR")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: 0x060709))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PulsoTheme.amber)
                        .cornerRadius(4)
                }
            }

            // Lista de Secciones Existentes en la Canción
            if !vm.currentSong.sections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SECCIONES ACTUALES (\(vm.currentSong.sections.count)):")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(vm.currentSong.sections) { sec in
                                HStack(spacing: 8) {
                                    Text(sec.shortName)
                                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                        .foregroundColor(.white)
                                        .frame(width: 22, height: 18)
                                        .background(sec.color)
                                        .cornerRadius(3)

                                    Text(sec.name)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(PulsoTheme.ink)

                                    Spacer()

                                    Text("c.\(sec.startBar) (\(sec.lengthBars)c)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(PulsoTheme.mut)

                                    Button(action: {
                                        vm.removeSection(id: sec.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 9))
                                            .foregroundColor(PulsoTheme.red.opacity(0.8))
                                            .frame(width: 20, height: 20)
                                            .background(PulsoTheme.red.opacity(0.1))
                                            .cornerRadius(3)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PulsoTheme.surface)
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(PulsoTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.75), radius: 24, x: 0, y: 12)
    }
}

private struct ArrangerPositionLabel: View {
    @ObservedObject var position: MusicalPosition
    let atCursor: Bool
    let endBar: Int

    var body: some View {
        Text(atCursor ? "Compás actual (c.\(position.bar))" : "Al final (c.\(endBar))")
    }
}
