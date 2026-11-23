import SwiftUI

/// Replica of `.cloud-choice-card` modal ("AGREGAR CANCIÓN AL SETLIST") from PULSO Web
struct AddSongChoiceModalView: View {
    @ObservedObject var vm: ShowViewModel

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    vm.showingAddSongModal = false
                }

            // Modal Box
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.square.fill.on.square.fill")
                            .font(.system(size: 15))
                            .foregroundColor(PulsoTheme.amber)
                        Text("AGREGAR CANCIÓN AL SETLIST")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)
                    }

                    Spacer()

                    Button(action: { vm.showingAddSongModal = false }) {
                        Text("✕")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 28, height: 28)
                            .background(PulsoTheme.raise)
                            .cornerRadius(4)
                    }
                }

                Text("Selecciona el origen de tus multitracks para agregarlos al setlist:")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PulsoTheme.mut)

                // 2 Options Grid (Nube vs Local)
                HStack(spacing: 16) {
                    // Option 1: NUBE
                    Button(action: {
                        vm.showingAddSongModal = false
                        vm.showingCloudCatalogModal = true
                    }) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(PulsoTheme.amber.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Circle().stroke(PulsoTheme.amber.opacity(0.3), lineWidth: 1)
                                    )
                                Image(systemName: "icloud.and.arrow.down.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(PulsoTheme.amber)
                            }

                            Text("CATÁLOGO EN LA NUBE")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(PulsoTheme.ink)

                            Text("Explora y descarga canciones formateadas en tu servidor Debian (stems.tld-list.lat).")
                                .font(.system(size: 10))
                                .foregroundColor(PulsoTheme.mut)
                                .multilineTextAlignment(.center)
                                .frame(height: 36)

                            HStack(spacing: 4) {
                                Text("EXPLORAR NUBE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(PulsoTheme.amber)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(PulsoTheme.amber)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(PulsoTheme.raise)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(PulsoTheme.border, lineWidth: 1)
                        )
                        .cornerRadius(12)
                    }

                    // Option 2: LOCAL
                    Button(action: {
                        vm.showingAddSongModal = false
                        vm.showingLocalFilePicker = true
                    }) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Circle().stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                                Image(systemName: "externaldrive.fill.badge.plus")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color.blue)
                            }

                            Text("ARCHIVO LOCAL")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(PulsoTheme.ink)

                            Text("Carga un archivo .ZIP desde este dispositivo únicamente para uso local/offline.")
                                .font(.system(size: 10))
                                .foregroundColor(PulsoTheme.mut)
                                .multilineTextAlignment(.center)
                                .frame(height: 36)

                            HStack(spacing: 4) {
                                Text("CARGAR LOCAL")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.blue)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color.blue)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(PulsoTheme.raise)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(PulsoTheme.border, lineWidth: 1)
                        )
                        .cornerRadius(12)
                    }
                }
            }
            .padding(24)
            .frame(width: 520)
            .background(PulsoTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(PulsoTheme.border, lineWidth: 1)
            )
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.7), radius: 30, x: 0, y: 15)
        }
    }
}
