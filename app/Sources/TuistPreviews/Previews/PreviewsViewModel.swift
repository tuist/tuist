import Foundation
import SwiftUI
import TuistServer

@Observable
final class PreviewsViewModel: Sendable {
    private let listPreviewsService: ListPreviewsServicing

    private(set) var previews: [TuistServer.Preview] = []

    init(
        listPreviewsService: ListPreviewsServicing = ListPreviewsService()
    ) {
        self.listPreviewsService = listPreviewsService
    }

    func onAppear() async throws {
        previews = try! await listPreviewsService.listPreviews(
            displayName: nil,
            specifier: nil,
            supportedPlatforms: [],
            page: nil,
            pageSize: nil,
            distinctField: nil,
            fullHandle: "tuist/tuist",
            serverURL: URL(string: "https://tuist.dev")!
        )
    }
}
