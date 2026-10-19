import Foundation

enum DesktopSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case previews = "Previews"

    var id: String { rawValue }
    var systemImage: String { self == .home ? "house" : "app.dashed" }
}

struct DesktopNavigation {
    var section: DesktopSection? = .home
    var selectedPreviewID: String?

    var activePreviewID: String? {
        section == .previews ? selectedPreviewID : nil
    }

    @MainActor
    mutating func openPreview(_ id: String, in model: DesktopPreviewsModel) {
        if !model.filteredPreviews.contains(where: { $0.id == id }) {
            model.clearFilters()
        }
        selectedPreviewID = id
        section = .previews
    }

    mutating func validateSelection(among previewIDs: [String]) {
        guard section == .previews, let selectedPreviewID, !previewIDs.contains(selectedPreviewID) else { return }
        self.selectedPreviewID = nil
    }
}
