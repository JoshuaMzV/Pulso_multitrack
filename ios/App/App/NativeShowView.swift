import SwiftUI
import UIKit

/// Root View combining Header and Modern Show or Mixer mode
struct PulsoRootView: View {
    @StateObject private var vm = ShowViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // App Header (Transport, Time, Bars, Mode Switcher)
            AppHeaderView(vm: vm)

            // Content View (SHOW or EDICIÓN)
            if vm.mode == .show {
                ModernShowView(vm: vm)
            } else {
                StemsMixerView(vm: vm)
            }
        }
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
