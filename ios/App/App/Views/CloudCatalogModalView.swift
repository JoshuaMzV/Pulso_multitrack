import SwiftUI

/// Modal que muestra el catálogo de canciones disponible en el servidor Debian / Cloudflare CDN
struct CloudCatalogModalView: View {
    @ObservedObject var vm: ShowViewModel
    @State private var searchText: String = ""

    var filteredSongs: [CloudSong] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return vm.cloudCatalog
        }
        let q = searchText.lowercased()
        return vm.cloudCatalog.filter {
            $0.title.lowercased().contains(q) ||
            ($0.artist?.lowercased().contains(q) ?? false) ||
            ($0.key?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        ZStack {
            // Fondo oscuro difuminado
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    vm.showingCloudCatalogModal = false
                }

            VStack(spacing: 0) {
                // Header del Modal
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down.fill")
                        .font(.system(size: 18))
                        .foregroundColor(PulsoTheme.amber)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("CATÁLOGO DE MULTITRACKS EN LA NUBE")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundColor(PulsoTheme.ink)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hexString: "#26a69a"))
                                    .frame(width: 6, height: 6)
                                Text("ONLINE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hexString: "#26a69a"))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hexString: "#26a69a").opacity(0.12))
                            .cornerRadius(4)
                        }

                        Text("Servidor: stems.tld-list.lat • Descarga directa de stems en alta fidelidad")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                    }

                    Spacer()

                    // Botón refrescar
                    Button(action: {
                        Task { await vm.loadCloudCatalog() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 30, height: 30)
                            .background(PulsoTheme.raise)
                            .cornerRadius(6)
                    }

                    // Botón Cerrar
                    Button(action: {
                        vm.showingCloudCatalogModal = false
                    }) {
                        Text("✕")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 30, height: 30)
                            .background(PulsoTheme.raise)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
                .background(PulsoTheme.card)

                Divider()
                    .background(PulsoTheme.border)

                // Barra de Búsqueda
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(PulsoTheme.mut)

                    TextField("Buscar canción por título, artista o tono...", text: $searchText)
                        .font(.system(size: 12))
                        .foregroundColor(PulsoTheme.ink)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(PulsoTheme.mut)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PulsoTheme.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PulsoTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // Contenido de la lista
                if vm.isLoadingCatalog {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PulsoTheme.amber))
                            .scaleEffect(1.2)
                        Text("Cargando catálogo desde el servidor...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                        Spacer()
                    }
                    .frame(height: 320)
                } else if filteredSongs.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "music.note.slash")
                            .font(.system(size: 32))
                            .foregroundColor(PulsoTheme.mut)
                        Text(vm.cloudCatalog.isEmpty ? "No se pudieron obtener canciones del servidor." : "No se encontraron canciones para '\(searchText)'.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)

                        Button(action: {
                            Task { await vm.loadCloudCatalog() }
                        }) {
                            Text("Reintentar conexión")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(PulsoTheme.amber)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(PulsoTheme.amber.opacity(0.12))
                                .cornerRadius(6)
                        }
                        Spacer()
                    }
                    .frame(height: 320)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(filteredSongs) { song in
                                cloudSongRow(song)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .frame(maxHeight: 460)
                }

                // Footer con contador
                Divider()
                    .background(PulsoTheme.border)

                HStack {
                    Text("\(filteredSongs.count) de \(vm.cloudCatalog.count) canciones disponibles")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    Spacer()

                    Button(action: {
                        vm.showingCloudCatalogModal = false
                    }) {
                        Text("LISTO")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(PulsoTheme.raise)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(PulsoTheme.card)
            }
            .frame(maxWidth: 680)
            .background(PulsoTheme.bg)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(PulsoTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
            .padding(24)
        }
        .onAppear {
            if vm.cloudCatalog.isEmpty {
                Task { await vm.loadCloudCatalog() }
            }
        }
    }

    // MARK: - Row View
    @ViewBuilder
    private func cloudSongRow(_ song: CloudSong) -> some View {
        let isAlreadyInSetlist = vm.setlist.songs.contains(where: {
            $0.title.lowercased() == song.title.lowercased()
        })
        let progress = vm.downloadProgress[song.id]
        let isDownloading = progress != nil && progress! < 1.0

        HStack(spacing: 14) {
            // Portada de la Canción
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(PulsoTheme.raise)
                    .frame(width: 54, height: 54)

                if let coverStr = song.cover, let coverUrl = URL(string: coverStr) {
                    AsyncImage(url: coverUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 54, height: 54)
                                .clipped()
                                .cornerRadius(8)
                        default:
                            fallbackCover(song)
                        }
                    }
                } else {
                    fallbackCover(song)
                }
            }

            // Información de la Canción
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(PulsoTheme.ink)
                    .lineLimit(1)

                Text(song.artist ?? "Desconocido")
                    .font(.system(size: 11))
                    .foregroundColor(PulsoTheme.mut)
                    .lineLimit(1)

                // Badges (BPM, Tono, Pistas)
                HStack(spacing: 6) {
                    if let bpm = song.bpm {
                        badgeView("\(Int(bpm)) BPM")
                    }
                    if let key = song.key, !key.isEmpty {
                        badgeView(key, isKey: true)
                    }
                    let stemsCount = song.stems?.count ?? 0
                    if stemsCount > 0 {
                        badgeView("\(stemsCount) pistas")
                    }
                }
            }

            Spacer()

            // Botón de Acción
            if isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: progress ?? 0.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: PulsoTheme.amber))
                        .frame(width: 110)
                    Text("Descargando \(Int((progress ?? 0.0) * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.amber)
                }
                .padding(.horizontal, 8)
            } else if isAlreadyInSetlist {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hexString: "#26a69a"))
                    Text("EN SETLIST")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hexString: "#26a69a"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hexString: "#26a69a").opacity(0.12))
                .cornerRadius(6)
            } else {
                Button(action: {
                    vm.downloadAndAddSong(song)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text("AGREGAR")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(PulsoTheme.bg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PulsoTheme.amber)
                    .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(PulsoTheme.card)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isAlreadyInSetlist ? Color(hexString: "#26a69a").opacity(0.3) : PulsoTheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func fallbackCover(_ song: CloudSong) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "waveform")
                .font(.system(size: 16))
                .foregroundColor(PulsoTheme.amber)
            if let key = song.key {
                Text(key)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.mut)
            }
        }
    }

    @ViewBuilder
    private func badgeView(_ text: String, isKey: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: isKey ? .black : .semibold, design: .monospaced))
            .foregroundColor(isKey ? PulsoTheme.amber : PulsoTheme.mut)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PulsoTheme.raise)
            .cornerRadius(4)
    }
}
