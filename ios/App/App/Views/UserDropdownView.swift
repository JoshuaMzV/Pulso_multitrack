import SwiftUI

/// Replica of `.user-dropdown` from PULSO Web
struct UserDropdownView: View {
    @ObservedObject var vm: ShowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text(vm.currentUser.avatar)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Color(hex: 0x111111))
                    .frame(width: 28, height: 28)
                    .background(PulsoTheme.amber)
                    .cornerRadius(14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vm.currentUser.username)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PulsoTheme.ink)

                        Text(vm.currentUser.role.rawValue)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(PulsoTheme.purple)
                            .cornerRadius(3)
                    }

                    Text("Modo local")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)
                }

                Spacer()
            }
            .padding(12)

            Divider().background(PulsoTheme.line)

            // Item 1: Iniciar Sesión
            Button(action: {
                vm.showingUserDropdown = false
                vm.showingAuthModal = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 12))
                        .foregroundColor(PulsoTheme.amber)
                    Text("Iniciar Sesión")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PulsoTheme.ink)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            // Item 2: Canjear Invitación
            Button(action: {
                vm.showingUserDropdown = false
                vm.showingAuthModal = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 12))
                        .foregroundColor(PulsoTheme.amber)
                    Text("Canjear Invitación")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PulsoTheme.ink)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider().background(PulsoTheme.line)

            // Item 3: Tema Claro / Oscuro
            HStack(spacing: 10) {
                Image(systemName: vm.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PulsoTheme.amber)
                Text(vm.isDarkMode ? "Tema oscuro" : "Tema claro")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PulsoTheme.ink)
                Spacer()
                Toggle("", isOn: $vm.isDarkMode)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: PulsoTheme.amber))
                    .scaleEffect(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            // Item 4: Cerrar Sesión (if logged in)
            if vm.isLoggedIn {
                Divider().background(PulsoTheme.line)

                Button(action: {
                    vm.logout()
                    vm.showingUserDropdown = false
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12))
                            .foregroundColor(PulsoTheme.red)
                        Text("Cerrar Sesión")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PulsoTheme.red)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(width: 240)
        .background(PulsoTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PulsoTheme.border, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.6), radius: 16, x: 0, y: 8)
    }
}
