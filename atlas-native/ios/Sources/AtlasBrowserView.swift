import Combine
import SwiftUI
#if os(macOS)
import AppKit
#else
import SafariServices
#endif

private struct AtlasServerKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

extension EnvironmentValues {
    var atlasServer: URL? {
        get { self[AtlasServerKey.self] }
        set { self[AtlasServerKey.self] = newValue }
    }
}

struct AtlasBrowserButton: View {
    let screen: String
    var recordID: String?
    @Environment(\.atlasServer) private var server
    @Environment(\.atlasNavigation) private var navigation
    @State private var showingBrowser = false

    var body: some View {
        if let server, let destination = AtlasDestination(screen: screen, recordID: recordID, server: server) {
            #if os(macOS)
            Button("Open in browser", systemImage: "safari") {
                guard let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.org")!) else { return }
                NSWorkspace.shared.open([destination.browserURL], withApplicationAt: browser,
                                        configuration: NSWorkspace.OpenConfiguration())
            }
            #else
            Button("Open in browser", systemImage: "safari") { showingBrowser = true }
                .sheet(isPresented: $showingBrowser) { AtlasBrowserView(url: destination.browserURL).ignoresSafeArea() }
                .onReceive(linkChanges) { _ in showingBrowser = false }
            #endif
        }
    }

    private var linkChanges: AnyPublisher<Void, Never> {
        guard let navigation else { return Empty().eraseToAnyPublisher() }
        return navigation.$revision.dropFirst().map { _ in () }
            .merge(with: navigation.$message.dropFirst().compactMap { $0 }.map { _ in () })
            .eraseToAnyPublisher()
    }
}

#if os(iOS)
// An embedded browser explicitly opts out of Universal Link handoff to this app.
private struct AtlasBrowserView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
