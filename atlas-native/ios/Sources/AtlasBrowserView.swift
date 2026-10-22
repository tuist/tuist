import Combine
import SafariServices
import SwiftUI

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
            Button("Open in browser", systemImage: "safari") { showingBrowser = true }
                .sheet(isPresented: $showingBrowser) { AtlasBrowserView(url: destination.browserURL).ignoresSafeArea() }
                .onReceive(linkChanges) { _ in showingBrowser = false }
        }
    }

    private var linkChanges: AnyPublisher<Void, Never> {
        guard let navigation else { return Empty().eraseToAnyPublisher() }
        return navigation.$revision.dropFirst().map { _ in () }
            .merge(with: navigation.$message.dropFirst().compactMap { $0 }.map { _ in () })
            .eraseToAnyPublisher()
    }
}

// An embedded browser explicitly opts out of Universal Link handoff to this app.
private struct AtlasBrowserView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
