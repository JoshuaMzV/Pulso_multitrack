import SwiftUI

/// Replica of `#arrangerPanel` from PULSO Web
struct ArrangerSubmenuPanel: View {
    @ObservedObject var vm: ShowViewModel
    @State private var customSectionName: String = ""

    let defaultLabels: [(name: String, color: Color)] = [
        ("INTRO", PulsoTheme.blue),
        ("VERSO", PulsoTheme.teal),
        ("PRECORO", PulsoTheme.amber),
        ("CORO", PulsoTheme.red),
        ("PUENTE", PulsoTheme.purple),
        ("FINAL", PulsoTheme.textDim)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.split.2x2")
                        .font(.system(size: 13))
                        .foregroundColor(PulsoTheme.amber)
                    Text("ARRANGER")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(PulsoTheme.ink)
                }

                Spacer()

                Button(action: { vm.showingArrangerPanel = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PulsoTheme.mut)
                        .frame(width: 22, height: 22)
                        .background(PulsoTheme.raise)
                        .cornerRadius(11)
                }
            }

            Text("Toca una sección para agregarla al timeline:")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(PulsoTheme.mut)

            // Grid of Section Badges
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(defaultLabels, id: \.name) { item in
                    Button(action: {
                        vm.addSection(name: item.name, color: item.color)
                    }) {
                        Text(item.name)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(PulsoTheme.raise)
                            .overlay(
                                Rectangle()
                                    .fill(item.color)
                                    .frame(height: 2),
                                alignment: .bottom
                            )
                            .cornerRadius(4)
                    }
                }
            }

            // Custom Section Field
            HStack(spacing: 6) {
                TextField("Escribe sección...", text: $customSectionName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(PulsoTheme.raise)
                    .cornerRadius(4)

                Button(action: {
                    let trimmed = customSectionName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    vm.addSection(name: trimmed.uppercased(), color: PulsoTheme.teal)
                    customSectionName = ""
                }) {
                    Text("+ OTRO")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: 0x060709))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PulsoTheme.amber)
                        .cornerRadius(4)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(PulsoTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.7), radius: 20, x: 0, y: 10)
    }
}
