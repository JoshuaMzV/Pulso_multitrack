import SwiftUI

/// Modal para seleccionar, crear y guardar setlists asociadas a la cuenta activa
struct SetlistSelectorModalView: View {
    @ObservedObject var vm: ShowViewModel
    @State private var showingCreateForm: Bool = false
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
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18))
                        .foregroundColor(PulsoTheme.amber)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SETLISTS DISPONIBLES")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)

                        Text("Cuenta: @\(vm.currentUser.username) • Rol: \(vm.currentUser.role.rawValue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                    }

                    Spacer()

                    // Botón refrescar
                    Button(action: {
                        Task { await vm.loadSetlistsFromBackend() }
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
                        Text("✕")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 32, height: 32)
                            .background(PulsoTheme.raise)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background(PulsoTheme.card)

                Divider().background(PulsoTheme.border)

                // Botón / Formulario para Crear Nueva Setlist
                VStack(spacing: 12) {
                    if !showingCreateForm {
                        Button(action: { showingCreateForm = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text("+ CREAR NUEVA SETLIST")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                            }
                            .foregroundColor(PulsoTheme.amber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(PulsoTheme.amber.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(PulsoTheme.amber.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(8)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("NUEVA SETLIST")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundColor(PulsoTheme.amber)

                            TextField("Nombre (Ej. CULTO DOMINGO, ENSAYO)", text: $newName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(PulsoTheme.ink)
                                .padding(10)
                                .background(PulsoTheme.panel)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))

                            TextField("Descripción (Opcional)", text: $newDescription)
                                .font(.system(size: 12))
                                .foregroundColor(PulsoTheme.ink)
                                .padding(10)
                                .background(PulsoTheme.panel)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))

                            HStack(spacing: 10) {
                                Button(action: {
                                    showingCreateForm = false
                                    newName = ""
                                    newDescription = ""
                                }) {
                                    Text("CANCELAR")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(PulsoTheme.mut)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(PulsoTheme.raise)
                                        .cornerRadius(6)
                                }

                                Spacer()

                                Button(action: {
                                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                                    guard !trimmed.isEmpty else { return }
                                    vm.createNewSetlist(name: trimmed, description: newDescription)
                                    showingCreateForm = false
                                    newName = ""
                                    newDescription = ""
                                }) {
                                    Text("CREAR Y ABRIR")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .foregroundColor(PulsoTheme.bg)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(PulsoTheme.amber)
                                        .cornerRadius(6)
                                }
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(14)
                        .background(PulsoTheme.raise)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(PulsoTheme.border, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

                // Lista de Setlists
                ScrollView {
                    VStack(spacing: 10) {
                        if vm.isLoadingSetlists {
                            HStack(spacing: 10) {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: PulsoTheme.amber))
                                Text("Cargando setlists del servidor...")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(PulsoTheme.mut)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                        } else if vm.availableSetlists.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "square.stack.3d.slash")
                                    .font(.system(size: 28))
                                    .foregroundColor(PulsoTheme.mut)
                                Text("No hay setlists guardadas en la cuenta.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(PulsoTheme.mut)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                        } else {
                            ForEach(vm.availableSetlists) { sl in
                                setlistRow(sl)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: 380)

                Divider().background(PulsoTheme.border)

                // Barra Inferior de Guardado
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SETLIST ACTIVA:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PulsoTheme.mut)
                        Text(vm.setlist.name)
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(PulsoTheme.ink)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Botón Guardar Cambios en Servidor
                    Button(action: {
                        Task { await vm.saveSetlistsToBackend() }
                    }) {
                        HStack(spacing: 7) {
                            if vm.isSavingSetlist {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: PulsoTheme.bg))
                                    .scaleEffect(0.8)
                                Text("GUARDANDO...")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                            } else if vm.setlistSavedSuccess {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                Text("GUARDADO")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                            } else {
                                Image(systemName: "icloud.and.arrow.up.fill")
                                    .font(.system(size: 12))
                                Text("GUARDAR EN SERVIDOR")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                            }
                        }
                        .foregroundColor(PulsoTheme.bg)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(vm.setlistSavedSuccess ? Color(hexString: "#26a69a") : PulsoTheme.amber)
                        .cornerRadius(8)
                    }
                    .disabled(vm.isSavingSetlist)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(PulsoTheme.card)
            }
            .frame(maxWidth: 620)
            .background(PulsoTheme.bg)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(PulsoTheme.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.7), radius: 25, x: 0, y: 15)
            .padding(24)
        }
        .onAppear {
            Task { await vm.loadSetlistsFromBackend() }
        }
    }

    @ViewBuilder
    private func setlistRow(_ sl: SetlistItem) -> some View {
        let isActive = sl.id == vm.setlist.id

        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? PulsoTheme.amber.opacity(0.18) : PulsoTheme.raise)
                    .frame(width: 44, height: 44)

                Image(systemName: isActive ? "checkmark.circle.fill" : "square.stack.3d.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isActive ? PulsoTheme.amber : PulsoTheme.mut)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(sl.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isActive ? PulsoTheme.amber : PulsoTheme.ink)

                    if isActive {
                        Text("ACTIVA")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(PulsoTheme.bg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PulsoTheme.amber)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 6) {
                    if let desc = sl.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundColor(PulsoTheme.mut)
                    }
                    if let grp = sl.group_name ?? sl.group_id {
                        Text("• Grupo: \(grp)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PulsoTheme.dim)
                    }
                }
                .lineLimit(1)
            }

            Spacer()

            // Badge de número de canciones
            Text("\(sl.songs.count) \(sl.songs.count == 1 ? "canción" : "canciones")")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(PulsoTheme.mut)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PulsoTheme.raise)
                .cornerRadius(4)

            // Botón Seleccionar / Activar
            if !isActive {
                Button(action: {
                    vm.switchSetlist(to: sl)
                }) {
                    Text("ABRIR")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(PulsoTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PulsoTheme.raise)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PulsoTheme.border, lineWidth: 1))
                }
            }
        }
        .padding(12)
        .background(isActive ? PulsoTheme.raise.opacity(0.6) : PulsoTheme.card)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? PulsoTheme.amber.opacity(0.4) : PulsoTheme.border, lineWidth: 1)
        )
    }
}
