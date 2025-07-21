import Foundation
import SwiftUI
import TuistServer

@Observable
final class PreviewViewModel: Sendable {
    private let deletePreviewService: DeletePreviewServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let getPreviewService: GetPreviewServicing

    private(set) var preview: ServerPreview?
    private(set) var isLoading: Bool
    private let previewId: String
    private let fullHandle: String

    convenience init(
        preview: ServerPreview,
        fullHandle: String
    ) {
        self.init(
            preview: preview,
            previewId: preview.id,
            isLoading: false,
            fullHandle: fullHandle
        )
    }

    convenience init(
        previewId: String,
        fullHandle: String
    ) {
        self.init(
            preview: nil,
            previewId: previewId,
            isLoading: true,
            fullHandle: fullHandle
        )
    }

    init(
        preview: ServerPreview?,
        previewId: String,
        isLoading _: Bool,
        fullHandle: String,
        deletePreviewService: DeletePreviewServicing = DeletePreviewService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        getPreviewService: GetPreviewServicing = GetPreviewService()
    ) {
        self.preview = preview
        self.previewId = previewId
        isLoading = false
        self.fullHandle = fullHandle
        self.deletePreviewService = deletePreviewService
        self.serverEnvironmentService = serverEnvironmentService
        self.getPreviewService = getPreviewService
    }

    func onAppear() async throws {
        guard preview == nil else { return }
        isLoading = true
        defer { isLoading = false }

        preview = try await getPreviewService.getPreview(
            previewId,
            fullHandle: fullHandle,
            serverURL: serverEnvironmentService.url()
        )
    }

    func deletePreview(_ preview: ServerPreview) async throws {
        try await deletePreviewService.deletePreview(
            preview.id,
            fullHandle: fullHandle,
            serverURL: serverEnvironmentService.url()
        )
    }
}
