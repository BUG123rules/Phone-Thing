import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationController.shared.mask
    }
}

final class OrientationController {
    static let shared = OrientationController()

    private(set) var mask: UIInterfaceOrientationMask = .landscape

    func apply(layoutOrientation: String) {
        let normalized = layoutOrientation.lowercased()
        let newMask: UIInterfaceOrientationMask = normalized == "portrait" ? .portrait : .landscape
        let targetOrientation: UIInterfaceOrientation = normalized == "portrait" ? .portrait : .landscapeRight

        mask = newMask

        UIDevice.current.setValue(targetOrientation.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}

@main
struct PhoneThingRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
