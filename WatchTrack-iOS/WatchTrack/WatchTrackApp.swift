import SwiftUI

@main
struct WatchTrackApp: App {
    @StateObject private var webServer = LocalWebServer()

    var body: some Scene {
        WindowGroup {
            ContentView(server: webServer)
        }
    }
}
