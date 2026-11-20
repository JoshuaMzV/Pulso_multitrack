import SwiftUI

enum AuthModalTab {
    case login
    case register
}

/// Exact replica of `.modal-box` for "ACCESO PULSO" from PULSO Web
struct AuthModalView: View {
    @ObservedObject var vm: ShowViewModel
    @State private var currentTab: AuthModalTab = .login
    @State private var usernameInput: String = ""
    @State private var passwordInput: String = ""
    @State private var inviteCodeInput: String = ""
    @State private var alertMessage: String? = nil
    @State private var alertIsError: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var showServerConfig: Bool = false
    @State private var serverURLInput: String = ""

    var body: some View {
        ZStack {
            // Dark Backdrop with blur
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    vm.showingAuthModal = false
                }

            // Modal Box (.modal-box)
            VStack(alignment: .leading, spacing: 0) {
                // 1. Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(PulsoTheme.amber)

                        Text("ACCESO PULSO")
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)
                    }

                    Spacer()

                    Button(action: { vm.showingAuthModal = false }) {
                        Text("✕")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(PulsoTheme.mut)
                            .frame(width: 28, height: 28)
                            .background(PulsoTheme.raise)
                            .cornerRadius(4)
                    }
                }
                .padding(.bottom, 12)

                // Server URL Config Row
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 10))
                        .foregroundColor(PulsoTheme.amber)

                    Text("Servidor:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PulsoTheme.mut)

                    Text(vm.serverURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PulsoTheme.ink2)
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        serverURLInput = vm.serverURL
                        showServerConfig.toggle()
                    }) {
                        Text(showServerConfig ? "Ocultar" : "Cambiar")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(PulsoTheme.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PulsoTheme.raise)
                            .cornerRadius(3)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PulsoTheme.panel2)
                .cornerRadius(6)
                .padding(.bottom, 12)

                if showServerConfig {
                    HStack(spacing: 8) {
                        TextField("http://192.168.1.X:5000", text: $serverURLInput)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PulsoTheme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(PulsoTheme.raise)
                            .cornerRadius(4)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button(action: {
                            if !serverURLInput.isEmpty {
                                vm.serverURL = serverURLInput
                                showServerConfig = false
                            }
                        }) {
                            Text("Guardar")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: 0x0E0C0A))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(PulsoTheme.amber)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.bottom, 12)
                }

                // 2. Tabs (.auth-tabs)
                HStack(spacing: 16) {
                    tabButton(title: "INICIAR SESIÓN", tab: .login)
                    tabButton(title: "CANJEAR CÓDIGO", tab: .register)
                    Spacer()
                }
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(PulsoTheme.line),
                    alignment: .bottom
                )
                .padding(.bottom, 18)

                // 3. Alerts
                if let alert = alertMessage {
                    Text(alert)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(alertIsError ? PulsoTheme.red : PulsoTheme.green)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(alertIsError ? PulsoTheme.red.opacity(0.15) : PulsoTheme.green.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(alertIsError ? PulsoTheme.red.opacity(0.3) : PulsoTheme.green.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(6)
                        .padding(.bottom, 14)
                }

                // 4. Form Content
                if currentTab == .login {
                    loginForm
                } else {
                    registerForm
                }
            }
            .padding(24)
            .frame(width: 440)
            .background(PulsoTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(PulsoTheme.border, lineWidth: 1)
            )
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.7), radius: 30, x: 0, y: 15)
        }
    }

    // MARK: - Tab Button

    private func tabButton(title: String, tab: AuthModalTab) -> some View {
        let isActive = currentTab == tab
        return Button(action: {
            currentTab = tab
            alertMessage = nil
        }) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(isActive ? PulsoTheme.amber : PulsoTheme.mut)

                Rectangle()
                    .fill(isActive ? PulsoTheme.amber : Color.clear)
                    .frame(height: 2)
            }
        }
    }

    // MARK: - Login Form

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Username Field
            VStack(alignment: .leading, spacing: 6) {
                Text("NOMBRE DE USUARIO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(PulsoTheme.mut)

                TextField("Ej. pastor_david", text: $usernameInput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.raise)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PulsoTheme.line, lineWidth: 1)
                    )
                    .cornerRadius(6)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            // Password Field
            VStack(alignment: .leading, spacing: 6) {
                Text("CONTRASEÑA")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(PulsoTheme.mut)

                SecureField("••••••••", text: $passwordInput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.raise)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PulsoTheme.line, lineWidth: 1)
                    )
                    .cornerRadius(6)
            }

            // Buttons
            HStack(spacing: 10) {
                Button(action: { vm.showingAuthModal = false }) {
                    Text("Cancelar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PulsoTheme.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(PulsoTheme.raise)
                        .cornerRadius(6)
                }

                Button(action: performLogin) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: 0x060709)))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.right.to.line")
                                .font(.system(size: 12, weight: .bold))
                            Text("ENTRAR")
                                .font(.system(size: 12, weight: .heavy))
                        }
                    }
                    .foregroundColor(Color(hex: 0x060709))
                    .frame(maxWidth: .infinity * 1.6)
                    .frame(height: 38)
                    .background(isSubmitting ? PulsoTheme.amber.opacity(0.6) : PulsoTheme.amber)
                    .cornerRadius(6)
                }
                .disabled(isSubmitting)
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Register with Code Form

    private var registerForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Invite Code Field
            VStack(alignment: .leading, spacing: 6) {
                Text("CÓDIGO DE INVITACIÓN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(PulsoTheme.mut)

                TextField("Ej. USER-XXXX-XXXX", text: $inviteCodeInput)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(PulsoTheme.amber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.raise)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PulsoTheme.line, lineWidth: 1)
                    )
                    .cornerRadius(6)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)

                Text("Ingresa tu código de invitación para configurar tu cuenta y grupo.")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(PulsoTheme.mut)
            }

            // Username Desired Field
            VStack(alignment: .leading, spacing: 6) {
                Text("ELIGE TU NOMBRE DE USUARIO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(PulsoTheme.mut)

                TextField("Ej. lider_marcos", text: $usernameInput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.raise)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PulsoTheme.line, lineWidth: 1)
                    )
                    .cornerRadius(6)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            // Password Field
            VStack(alignment: .leading, spacing: 6) {
                Text("ELIGE UNA CONTRASEÑA")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(PulsoTheme.mut)

                SecureField("Mínimo 6 caracteres", text: $passwordInput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(PulsoTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(PulsoTheme.raise)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PulsoTheme.line, lineWidth: 1)
                    )
                    .cornerRadius(6)
            }

            // Buttons
            HStack(spacing: 10) {
                Button(action: { vm.showingAuthModal = false }) {
                    Text("Cancelar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PulsoTheme.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(PulsoTheme.raise)
                        .cornerRadius(6)
                }

                Button(action: performRegister) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: 0x060709)))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("CREAR CUENTA")
                                .font(.system(size: 12, weight: .heavy))
                        }
                    }
                    .foregroundColor(Color(hex: 0x060709))
                    .frame(maxWidth: .infinity * 1.6)
                    .frame(height: 38)
                    .background(isSubmitting ? PulsoTheme.amber.opacity(0.6) : PulsoTheme.amber)
                    .cornerRadius(6)
                }
                .disabled(isSubmitting)
            }
            .padding(.top, 10)
        }
    }

    private func performLogin() {
        let u = usernameInput.trimmingCharacters(in: .whitespaces)
        let p = passwordInput.trimmingCharacters(in: .whitespaces)

        guard !u.isEmpty else {
            alertMessage = "Ingresa tu nombre de usuario."
            alertIsError = true
            return
        }
        guard !p.isEmpty else {
            alertMessage = "Ingresa tu contraseña."
            alertIsError = true
            return
        }

        alertMessage = nil
        isSubmitting = true

        Task {
            do {
                try await vm.loginWithBackend(username: u, password: p)
                await MainActor.run {
                    self.isSubmitting = false
                    self.vm.showingAuthModal = false
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.alertMessage = error.localizedDescription
                    self.alertIsError = true
                }
            }
        }
    }

    private func performRegister() {
        let c = inviteCodeInput.trimmingCharacters(in: .whitespaces)
        let u = usernameInput.trimmingCharacters(in: .whitespaces)
        let p = passwordInput.trimmingCharacters(in: .whitespaces)

        guard !c.isEmpty else {
            alertMessage = "El código de invitación es requerido."
            alertIsError = true
            return
        }
        guard !u.isEmpty else {
            alertMessage = "Ingresa tu nombre de usuario."
            alertIsError = true
            return
        }
        guard !p.isEmpty else {
            alertMessage = "Ingresa tu contraseña."
            alertIsError = true
            return
        }

        alertMessage = nil
        isSubmitting = true

        Task {
            do {
                try await vm.registerWithBackend(username: u, password: p, inviteCode: c)
                await MainActor.run {
                    self.isSubmitting = false
                    self.vm.showingAuthModal = false
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.alertMessage = error.localizedDescription
                    self.alertIsError = true
                }
            }
        }
    }
}
