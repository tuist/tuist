import Foundation
import SwiftUI
import TuistServer

@Observable
final class PreviewViewModel: Sendable {
    private let deletePreviewService: DeletePreviewServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        deletePreviewService: DeletePreviewServicing = DeletePreviewService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.deletePreviewService = deletePreviewService
        self.serverEnvironmentService = serverEnvironmentService
    }

    func deletePreview(_ preview: ServerPreview, project: ServerProject) async throws {
        try await deletePreviewService.deletePreview(
            preview.id,
            fullHandle: project.fullName,
            serverURL: serverEnvironmentService.url()
        )
    }
}
