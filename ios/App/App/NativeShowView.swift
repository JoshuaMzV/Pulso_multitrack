import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Root View combining Header and Modern Show or Mixer mode
struct PulsoRootView: View {
    @StateObject private var vm = ShowViewModel()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // App Header (Transport, Time, Bars, Mode Switcher)
                AppHeaderView(vm: vm)

                // Content View (SHOW or EDICIÓN)
                if vm.mode == .show {
                    ModernShowView(vm: vm)
                } else {
                    EditionView(vm: vm)
                }
            }

            // Cloud Catalog Modal ("CATÁLOGO DE MULTITRACKS EN LA NUBE")
            if vm.showingCloudCatalogModal {
                CloudCatalogModalView(vm: vm)
                    .transition(.opacity)
            }

            // Add Song Choice Modal (Nube vs Local)
            if vm.showingAddSongModal {
                AddSongChoiceModalView(vm: vm)
                    .transition(.opacity)
            }

            // Setlist Selector Modal ("SETLISTS EN SERVIDOR")
            if vm.showingSetlistSelectorModal {
                SetlistSelectorModalView(vm: vm)
                    .transition(.opacity)
            }

            // Upload Song Wizard Modal ("SUBIR NUEVA CANCIÓN AL SERVIDOR")
            if vm.showingUploadSongWizard {
                UploadSongModalView(vm: vm)
                    .transition(.opacity)
            }

            // Transpose Modal ("TRANSPONER CANCIÓN")
            if vm.showingTransposeDialog {
                TransposeDialogView(vm: vm, isPresented: $vm.showingTransposeDialog)
                    .transition(.opacity)
            }

            // Auth Modal ("ACCESO PULSO")
            if vm.showingAuthModal {
                AuthModalView(vm: vm)
                    .transition(.opacity)
            }
        }
        .fileImporter(
            isPresented: $vm.showingLocalFilePicker,
            allowedContentTypes: [.zip, .audio],
            allowsMultipleSelection: true
        ) { result in
            vm.handleLocalFilesImported(result)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.showingAuthModal)
        .animation(.easeInOut(duration: 0.2), value: vm.showingCloudCatalogModal)
        .animation(.easeInOut(duration: 0.2), value: vm.showingAddSongModal)
        .animation(.easeInOut(duration: 0.2), value: vm.showingSetlistSelectorModal)
        .animation(.easeInOut(duration: 0.2), value: vm.showingUploadSongWizard)
        .animation(.easeInOut(duration: 0.2), value: vm.showingTransposeDialog)
        .preferredColorScheme(vm.isDarkMode ? .dark : .light)
        .background(PulsoTheme.bg.ignoresSafeArea())
    }
}

/// Root UIViewController for iOS SceneDelegate
final class NativeShowView: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 17/255, green: 17/255, blue: 17/255, alpha: 1.0)

        let hosting = UIHostingController(rootView: PulsoRootView())
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    override var prefersStatusBarHidden: Bool { true }
}
