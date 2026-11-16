import SwiftUI

/// Reusable modal for musical key transposition from PULSO Web
struct TransposeDialogView: View {
    @ObservedObject var vm: ShowViewModel
    @Binding var isPresented: Bool

    let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 16) {
                HStack {
                    Text("TRANSPONER CANCIÓN")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(PulsoTheme.textLight)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 24, height: 24)
                            .background(PulsoTheme.raise)
                            .cornerRadius(12)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(notes, id: \.self) { note in
                        let isSel = vm.currentSong.key == note
                        Button(action: {
                            vm.setSongKey(note)
                            isPresented = false
                        }) {
                            Text(note)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(isSel ? Color(hex: 0x111111) : PulsoTheme.textLight)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isSel ? PulsoTheme.amber : PulsoTheme.panel)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PulsoTheme.radSm)
                                        .stroke(isSel ? PulsoTheme.amber : PulsoTheme.border, lineWidth: 1)
                                )
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
            .frame(width: 420)
            .background(PulsoTheme.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: PulsoTheme.radMd)
                    .stroke(PulsoTheme.border, lineWidth: 1)
            )
            .cornerRadius(PulsoTheme.radMd)
            .shadow(color: Color.black.opacity(0.7), radius: 24, x: 0, y: 12)
        }
    }
}
