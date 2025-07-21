import Foundation
import NukeUI
import SwiftUI
import TuistErrorHandling
import TuistNoora
import TuistServer
import TuistSimulator
import XcodeGraph

public struct PreviewView: View {
    @EnvironmentObject private var errorHandler: ErrorHandling
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PreviewViewModel
    @State private var showingDeleteAlert = false

    private let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    public init(
        preview: ServerPreview,
        fullHandle: String
    ) {
        viewModel = PreviewViewModel(
            preview: preview,
            fullHandle: fullHandle
        )
    }

    public init(
        previewId: String,
        fullHandle: String
    ) {
        viewModel = PreviewViewModel(
            previewId: previewId,
            fullHandle: fullHandle
        )
    }

    public var body: some View {
        if let preview = viewModel.preview {
            ScrollView {
                VStack(spacing: Noora.Spacing.spacing7) {
                    PreviewViewHeader(preview: preview)
                    PreviewViewSupportedPlatforms(supportedPlatforms: preview.supportedPlatforms)

                    VStack(alignment: .leading, spacing: Noora.Spacing.spacing4) {
                        HStack {
                            Text("Details")
                                .font(.title2.weight(.medium))
                                .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                            Spacer()
                        }

                        VStack(spacing: 0) {
                            PreviewViewMetadataRow(title: "Created by") {
                                PreviewViewCreatedByBadge(preview: preview)
                            }
                            NooraDivider()
                            PreviewViewMetadataRow(title: "Created at") {
                                PreviewViewMetadataRowText(fullDateFormatter.string(from: preview.insertedAt))
                            }
                            NooraDivider()
                            if let bundleIdentifier = preview.bundleIdentifier {
                                PreviewViewMetadataRow(title: "Bundle identifier") {
                                    PreviewViewMetadataRowText(bundleIdentifier)
                                }
                            }
                            NooraDivider()
                            if let branch = preview.gitBranch {
                                PreviewViewMetadataRow(title: "Branch") {
                                    HStack(spacing: Noora.Spacing.spacing1) {
                                        NooraIcon(.gitBranch)
                                            .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                                            .frame(width: 16, height: 16)
                                        PreviewViewMetadataRowText(branch)
                                    }
                                }
                            }
                            NooraDivider()
                            if let sha = preview.gitCommitSHA {
                                PreviewViewMetadataRow(title: "Commit SHA") {
                                    PreviewViewMetadataRowText(sha)
                                }
                            }
                        }
                    }

                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        HStack(spacing: Noora.Spacing.spacing2) {
                            Text("Delete preview")
                                .font(.body.weight(.medium))
                                .padding(.vertical, 10)
                            Image(systemName: "trash")
                                .frame(width: 20, height: 20)
                        }
                        .foregroundColor(Noora.Colors.surfaceLabelDestructive)
                        .frame(maxWidth: .infinity)
                        .background(Noora.Colors.surfaceBackgroundSecondary)
                        .cornerRadius(Noora.CornerRadius.large)
                    }
                    .alert("Delete Preview", isPresented: $showingDeleteAlert) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete", role: .destructive) {
                            errorHandler.fireAndHandleError {
                                try await viewModel.deletePreview(preview)
                                dismiss()
                            }
                        }
                    } message: {
                        Text("Are you sure you want to delete this preview? This action cannot be undone.")
                    }
                }
                .padding(Noora.Spacing.spacing4)
            }
            .padding(.horizontal, Noora.Spacing.spacing4)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: preview.url)
                }
            }
            .background(Noora.Colors.surfaceBackgroundPrimary)
        } else {
            VStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.2)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Noora.Colors.surfaceBackgroundPrimary)
            .onAppear {
                errorHandler.fireAndHandleError {
                    try await viewModel.onAppear()
                }
            }
        }
    }
}
