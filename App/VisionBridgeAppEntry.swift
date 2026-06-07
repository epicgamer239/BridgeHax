import SwiftUI

@main
struct VisionBridgeAppEntry: App {
    @StateObject private var app = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .environmentObject(app.hearing)
        }
    }
}
