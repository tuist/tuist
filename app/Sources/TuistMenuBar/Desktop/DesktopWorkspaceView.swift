import AppKit
import SwiftUI
import TuistHome
import TuistProjects
import TuistServer

struct DesktopWorkspaceView: View {
    let accountHandle: String
    @Bindable var model: DesktopPreviewsModel
    @Binding var navigation: DesktopNavigation
    let activityModel: HomeActivityModel
    let handleAuthenticationError: (Error) -> Void
    let refresh: () -> Void
    let loadMore: () async -> Void

    private var selectedPreview: ServerPreview? {
        model.previews.first { $0.id == navigation.activePreviewID }
    }

    var body: some View {
        Group {
            if navigation.section == .previews {
                NavigationSplitView {
                    sidebar
                } content: {
                    previewList
                        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search loaded previews")
                        .navigationTitle("Previews")
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
                } detail: {
                    previewDetail
                }
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    home
                        .navigationTitle("Home")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh Previews", systemImage: "arrow.clockwise", action: refresh)
                    .help("Refresh Previews (⌘R)")
                    .disabled(model.isLoading || model.projectContext.isLoading)
            }
            if let preview = selectedPreview {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: preview.url) {
                        Label("Share Preview", systemImage: "square.and.arrow.up")
                    }
                    .help("Share Preview")
                    .accessibilityIdentifier("share-preview")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Open in Browser", systemImage: "safari") {
                        NSWorkspace.shared.open(preview.url)
                    }
                    .help("Open Preview in Browser")
                    .accessibilityIdentifier("open-preview-in-browser")
                }
            }
        }
        .focusedSceneValue(\.desktopPreviewActions, DesktopPreviewActions(
            preview: selectedPreview,
            canRefresh: !model.isLoading && !model.projectContext.isLoading,
            refresh: refresh
        ))
        .onChange(of: model.selectedProjectFullHandle) {
            navigation.selectedPreviewID = nil
            model.clearFilters()
        }
        .onChange(of: model.filteredPreviews.map(\.id)) {
            navigation.validateSelection(among: model.filteredPreviews.map(\.id))
        }
        .onChange(of: navigation.section) {
            navigation.validateSelection(among: model.filteredPreviews.map(\.id))
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ProjectSwitcher(context: model.projectContext)
                .padding(16)
            List(DesktopSection.allCases, selection: $navigation.section) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                Label(accountHandle, systemImage: "person.crop.circle")
                    .lineLimit(1)
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Home")
                        .font(.largeTitle.bold())
                    if let fullHandle = model.selectedProjectFullHandle {
                        Text(fullHandle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                HomeActivityView(model: activityModel, handleAuthenticationError: handleAuthenticationError)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Recent previews")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Button("View All Previews") { navigation.section = .previews }
                            .controlSize(.small)
                            .accessibilityIdentifier("view-all-previews")
                    }
                    if model.recentPreviews.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        VStack(spacing: 0) {
                            Divider()
                            ForEach(model.recentPreviews) { preview in
                                Button {
                                    navigation.openPreview(preview.id, in: model)
                                } label: {
                                    HStack(spacing: 16) {
                                        DesktopPreviewRow(preview: preview)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Show preview details")
                                .accessibilityIdentifier("recent-preview-\(preview.id)")
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.background)
    }

    @ViewBuilder
    private var previewDetail: some View {
        if let preview = selectedPreview,
           let fullHandle = model.selectedProjectFullHandle
        {
            DesktopPreviewDetail(preview: preview, fullHandle: fullHandle)
                .id("\(fullHandle)/\(preview.id)")
        } else {
            ContentUnavailableView(
                "Select a Preview",
                systemImage: "app.dashed",
                description: Text("Choose a preview to see its details and run it on a device.")
            )
        }
    }

    private var previewList: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Track", selection: $model.trackFilter) {
                    Text("All Tracks").tag(PreviewTrackFilter.all)
                    Text("No Track").tag(PreviewTrackFilter.unassigned)
                    Divider()
                    ForEach(model.availableTracks, id: \.self) { track in
                        Text(track).tag(PreviewTrackFilter.track(track))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("preview-track-filter")
                .help("Filter the loaded previews by release track")
                .disabled(model.isLoading || model.projectContext.isLoading)
                Spacer(minLength: 8)
                Button("Clear Filters") { model.clearFilters() }
                    .disabled(!model.hasActiveFilters)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if model.hasActiveFilters {
                Text("\(model.filteredPreviews.count) of \(model.previews.count) loaded previews")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            List(selection: $navigation.selectedPreviewID) {
                ForEach(model.filteredPreviews) { preview in
                    DesktopPreviewRow(preview: preview)
                        .tag(preview.id)
                }
                if model.hasMorePreviews, !model.isLoading {
                    paginationRow(for: model.nextPage)
                        .id(model.nextPage)
                }
            }
            .listStyle(.inset)
            .overlay { emptyState }
        }
    }

    private func paginationRow(for page: Int) -> some View {
        VStack(spacing: 8) {
            if let message = model.paginationErrorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await loadMore() }
                }
            } else {
                ProgressView("Loading more previews…")
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .selectionDisabled()
        .background {
            DesktopPaginationVisibility {
                Task {
                    guard model.nextPage == page, model.paginationErrorMessage == nil else { return }
                    await loadMore()
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoading || model.projectContext.isLoading, model.previews.isEmpty {
            ProgressView("Loading previews…")
        } else if let message = model.errorMessage, model.previews.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Previews", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: refresh)
            }
        } else if model.projects.isEmpty {
            ContentUnavailableView(
                "No Projects",
                systemImage: "folder",
                description: Text("Projects you have access to will appear here.")
            )
        } else if model.previews.isEmpty, !model.hasMorePreviews {
            ContentUnavailableView(
                "No Previews",
                systemImage: "app.dashed",
                description: Text("Share a preview with Tuist to see it here.")
            )
        } else if navigation.section == .previews, model.filteredPreviews.isEmpty, !model.hasMorePreviews {
            ContentUnavailableView {
                Label("No Matching Previews", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try another search or track.")
            } actions: {
                Button("Clear Filters") { model.clearFilters() }
            }
        }
    }
}

/// List can instantiate offscreen rows for accessibility, so pagination must observe actual AppKit clipping.
private struct DesktopPaginationVisibility: NSViewRepresentable {
    let onVisible: () -> Void

    func makeNSView(context _: Context) -> VisibilityView {
        let view = VisibilityView()
        view.setAccessibilityElement(false)
        view.onVisible = onVisible
        return view
    }

    func updateNSView(_ view: VisibilityView, context _: Context) {
        view.onVisible = onVisible
    }

    final class VisibilityView: NSView {
        var onVisible: (() -> Void)?
        private var wasVisible = false

        deinit { NotificationCenter.default.removeObserver(self) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeViewport()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            observeViewport()
        }

        override func hitTest(_: NSPoint) -> NSView? { nil }

        private func observeViewport() {
            let center = NotificationCenter.default
            center.removeObserver(self)
            if let clip = enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                center.addObserver(
                    self,
                    selector: #selector(checkVisibility),
                    name: NSView.boundsDidChangeNotification,
                    object: clip
                )
                var ancestor: NSView? = self
                while let view = ancestor, view !== clip {
                    view.postsFrameChangedNotifications = true
                    center.addObserver(
                        self,
                        selector: #selector(checkVisibility),
                        name: NSView.frameDidChangeNotification,
                        object: view
                    )
                    ancestor = view.superview
                }
            }
            checkVisibility()
        }

        @objc private func checkVisibility() {
            let visible = window != nil && enclosingScrollView != nil && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
            let becameVisible = visible && !wasVisible
            wasVisible = visible
            if becameVisible { onVisible?() }
        }
    }
}
