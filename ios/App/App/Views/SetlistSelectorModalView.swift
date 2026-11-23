import SwiftUI

/// Modal continuo de dos paneles para seleccionar, crear y guardar setlists en el servidor
struct SetlistSelectorModalView: View {
    @ObservedObject var vm: ShowViewModel
    @State private var newName: String = ""
    @State private var newDescription: String = ""

    var body: some View {
        ZStack {
            // Fondo oscuro semitransparente
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    vm.showingSetlistSelectorModal = false
                }

            VStack(spacing: 0) {
                // Header Superior
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18))
                        .foregroundColor(PulsoTheme.amber)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SETLISTS EN SERVIDOR")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)

                        Text("Servidor: stems.tld-list.lat • Cuenta: @\(vm.currentUser.username) (\(vm.currentUser.role.rawValue))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                    }

                    Spacer()

                    // Botón refrescar
                    Button(action: {
                        vm.loadSetlistsFromBackend()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 32, height: 32)
                            .background(PulsoTheme.raise)
                            .cornerRadius(6)
                    }

                    // Botón cerrar
                    Button(action: {
                        vm.showingSetlistSelectorModal = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 32, height: 32)
                            .background(PulsoTheme.raise)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(PulsoTheme.card)

                Divider().background(PulsoTheme.border)

                // Contenido Continuo: 2 Columnas (Panel Izquierdo: Lista | Panel Derecho: Crear Setlist)
                HStack(alignment: .top, spacing: 0) {
                    // Panel Izquierdo: Setlists Disponibles
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("LISTAS REGISTRADAS (\(vm.availableSetlists.count))")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(PulsoTheme.mut)
                            Spacer()
                            if vm.isLoadingSetlists {
                                ProgressView().tint(PulsoTheme.amber).scaleEffect(0.7)
                            }
                        }

                        ScrollView {
                            VStack(spacing: 8) {
                                if vm.availableSetlists.isEmpty && !vm.isLoadingSetlists {
                                    VStack(spacing: 8) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 28))
                                            .foregroundColor(PulsoTheme.dim)
                                        Text("No se encontraron setlists en el servidor")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(PulsoTheme.mut)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    ForEach(vm.availableSetlists) { s in
                                        setlistCard(s)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Divisor Vertical
                    Rectangle()
                        .fill(PulsoTheme.border)
                        .frame(width: 1)

                    // Panel Derecho Continuo: Crear Nueva Setlist
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.square.fill")
                                .font(.system(size: 15))
                                .foregroundColor(PulsoTheme.amber)
                            Text("CREAR NUEVA SETLIST")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(PulsoTheme.ink)
                        }

                        Text("Registra una nueva setlist en el servidor directamente desde este panel continuo.")
                            .font(.system(size: 10))
                            .foregroundColor(PulsoTheme.mut)
                            .lineSpacing(2)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOMBRE DE LA SETLIST *")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(PulsoTheme.mut)

                            TextField("Ej: Culto Domingo / Ensayo", text: $newName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(PulsoTheme.ink)
                                .padding(10)
                                .background(PulsoTheme.blackBox)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("DESCRIPCIÓN (OPCIONAL)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(PulsoTheme.mut)

                            TextField("Notas del servicio o fecha...", text: $newDescription)
                                .font(.system(size: 12))
                                .foregroundColor(PulsoTheme.ink)
                                .padding(10)
                                .background(PulsoTheme.blackBox)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))
                        }

                        Spacer()

                        Button(action: {
                            let trimmed = newName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            vm.createNewSetlist(name: trimmed, description: newDescription)
                            newName = ""
                            newDescription = ""
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("CREAR Y ABRIR")
                            }
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(newName.trimmingCharacters(in: .whitespaces).isEmpty ? PulsoTheme.border : PulsoTheme.amber)
                            .cornerRadius(6)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(20)
                    .frame(width: 320)
                    .background(PulsoTheme.panel)
                }

                Divider().background(PulsoTheme.border)

                // Footer con Guardar en Servidor
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(PulsoTheme.mut)
                        Text("Los cambios del setlist actual se sincronizan automáticamente con tu grupo.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                    }

                    Spacer()

                    Button(action: {
                        Task { await vm.saveSetlistsToBackend() }
                    }) {
                        HStack(spacing: 6) {
                            if vm.isSavingSetlist {
                                ProgressView().tint(.black).scaleEffect(0.7)
                            } else if vm.setlistSavedSuccess {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            } else {
                                Image(systemName: "icloud.and.arrow.up.fill")
                                    .font(.system(size: 11))
                            }
                            Text(vm.setlistSavedSuccess ? "¡GUARDADO!" : (vm.isSavingSetlist ? "GUARDANDO..." : "GUARDAR EN SERVIDOR"))
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                        }
                        .foregroundColor(Color(hex: 0x060709))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(vm.setlistSavedSuccess ? PulsoTheme.green : PulsoTheme.amber)
                        .cornerRadius(6)
                    }
                    .disabled(vm.isSavingSetlist)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(PulsoTheme.card)
            }
            .frame(width: 760, height: 480)
            .background(PulsoTheme.bg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PulsoTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.8), radius: 30, x: 0, y: 15)
        }
    }

    // MARK: - Tarjeta de cada Setlist

    private func setlistCard(_ s: SetlistItem) -> some View {
        let isSelected = s.id == vm.setlist.id

        return Button(action: {
            vm.switchSetlist(to: s)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? PulsoTheme.amber : PulsoTheme.raise)
                        .frame(width: 30, height: 30)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.black)
                    } else {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 12))
                            .foregroundColor(PulsoTheme.mut)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(s.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isSelected ? PulsoTheme.amber : PulsoTheme.ink)
                            .lineLimit(1)

                        if isSelected {
                            Text("ACTIVA")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundColor(PulsoTheme.amber)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(PulsoTheme.amber.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("\(s.songs.count) CANCIONES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.textDim)

                        if let desc = s.description, !desc.isEmpty {
                            Text("• \(desc)")
                                .font(.system(size: 9))
                                .foregroundColor(PulsoTheme.dim)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? PulsoTheme.amber : PulsoTheme.dim)
            }
            .padding(10)
            .background(isSelected ? PulsoTheme.amber.opacity(0.08) : PulsoTheme.cardBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? PulsoTheme.amber.opacity(0.6) : PulsoTheme.border, lineWidth: 1)
            )
        }
    }
}
