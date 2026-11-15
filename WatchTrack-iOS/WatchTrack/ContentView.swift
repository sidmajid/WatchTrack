import SwiftUI

struct ContentView: View {
    @ObservedObject var server: LocalWebServer

    private let accent = Color(red: 0.79, green: 0.95, blue: 0.42)

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.055, blue: 0.078)
                .ignoresSafeArea()

            if let url = server.baseURL {
                WatchTrackWebView(url: url)
                    // Keep the top edge inside the status-bar safe area.
                    // Extend the bottom edge so the web tab bar can use
                    // env(safe-area-inset-bottom) for the home indicator.
                    .ignoresSafeArea(.container, edges: .bottom)
            } else if let message = server.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)

                    Text("WatchTrack couldn’t start")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)

                    Button("Try again") {
                        server.start()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .tint(accent)
                    .padding(.top, 4)
                }
                .padding(32)
            } else {
                ProgressView("Preparing WatchTrack…")
                    .tint(accent)
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            server.start()
        }
        .preferredColorScheme(.dark)
    }
}
