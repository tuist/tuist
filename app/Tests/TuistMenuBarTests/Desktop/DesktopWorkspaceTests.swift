import AppKit
import Foundation
import Mockable
import SwiftUI
import Testing
import TuistAppStorage
import TuistServer
import TuistSimulator

@testable import TuistMenuBar
@testable import TuistProjects

@MainActor
struct DesktopWorkspaceTests {
    @Test(arguments: [900.0, 1280.0])
    func home_uses_the_main_area_without_a_preview_detail_column(width: Double) async throws {
        let fixture = try await makeFixture()
        let window = makeWindow(fixture: fixture, width: width)
        defer { window.close() }
        let tables = try await renderedTables(in: window, expectedCount: 1)
        let sidebar = try #require(tables.first)

        #expect(sidebar.numberOfRows == 2)
        #expect(window.contentView?.bounds.width == CGFloat(width))
        #expect(fixture.state.navigation.section == .home)
        #expect(fixture.state.navigation.activePreviewID == nil)
        #expect(fixture.model.recentPreviews.count == 3)
        let content = try #require(window.contentView)
        let splitViews = descendants(of: NSSplitView.self, in: content)
        #expect(!splitViews.isEmpty)
        #expect(splitViews.allSatisfy { $0.arrangedSubviews.count <= 2 })
        recordScreenshot(of: window, named: "sample-data-home-\(Int(width)).png")
    }

    @Test func opening_a_recent_preview_switches_to_the_resizable_browser_and_clears_conflicting_filters() async throws {
        let fixture = try await makeFixture()
        let window = makeWindow(fixture: fixture, width: 1280)
        defer { window.close() }
        _ = try await renderedTables(in: window, expectedCount: 1)
        fixture.model.searchText = "missing"
        fixture.model.trackFilter = .track("missing")

        fixture.state.navigation.openPreview("preview-1", in: fixture.model)

        let tables = try await renderedTables(in: window, expectedCount: 2)
        #expect(fixture.state.navigation.section == .previews)
        #expect(fixture.state.navigation.activePreviewID == "preview-1")
        #expect(!fixture.model.hasActiveFilters)
        let browser = try #require(tables.first { $0.numberOfRows == 5 })
        #expect(browser.frame.width >= 260)
        let content = try #require(window.contentView)
        #expect(descendants(of: NSSplitView.self, in: content).contains { $0.arrangedSubviews.count >= 2 })
        recordScreenshot(of: window, named: "sample-data-preview-detail.png")

        fixture.state.navigation.section = .home
        _ = try await renderedTables(in: window, expectedCount: 1)
        #expect(fixture.state.navigation.activePreviewID == nil)
        #expect(fixture.state.navigation.selectedPreviewID == "preview-1")
        recordScreenshot(of: window, named: "sample-data-restored-home.png")
    }

    @Test func returning_to_the_browser_preserves_matching_filters_and_selection() async throws {
        let fixture = try await makeFixture()
        fixture.state.navigation.openPreview("preview-1", in: fixture.model)
        let window = makeWindow(fixture: fixture, width: 900)
        defer { window.close() }
        _ = try await renderedTables(in: window, expectedCount: 2)
        fixture.state.navigation.section = .home
        _ = try await renderedTables(in: window, expectedCount: 1)
        fixture.model.searchText = "Sample App 1"
        fixture.model.trackFilter = .track("beta")

        fixture.state.navigation.section = .previews

        let tables = try await renderedTables(in: window, expectedCount: 2)
        #expect(fixture.state.navigation.activePreviewID == "preview-1")
        #expect(fixture.model.searchText == "Sample App 1")
        #expect(fixture.model.trackFilter == .track("beta"))
        #expect(tables.contains { $0.numberOfRows == 1 })
        #expect(window.contentView?.bounds.width == 900)
        recordScreenshot(of: window, named: "sample-data-filtered-browser-900.png")
    }

    @Test func switching_projects_clears_detail_but_keeps_the_browser_section() async throws {
        let fixture = try await makeFixture()
        fixture.state.navigation.openPreview("preview-1", in: fixture.model)
        let window = makeWindow(fixture: fixture, width: 1280)
        defer { window.close() }
        _ = try await renderedTables(in: window, expectedCount: 2)

        fixture.model.projectContext.selectProject("sample/other")
        try await fixture.model.loadSelectedProject()
        for _ in 0 ..< 100 where fixture.state.navigation.selectedPreviewID != nil {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(fixture.state.navigation.section == .previews)
        #expect(fixture.state.navigation.selectedPreviewID == nil)
        #expect(fixture.state.navigation.activePreviewID == nil)
        #expect(!fixture.model.hasActiveFilters)
    }

    @Test func filtering_out_a_selection_clears_it_without_affecting_home_recents() async throws {
        let fixture = try await makeFixture()
        fixture.state.navigation.openPreview("preview-1", in: fixture.model)
        fixture.model.searchText = "missing"

        fixture.state.navigation.validateSelection(among: fixture.model.filteredPreviews.map(\.id))

        #expect(fixture.state.navigation.selectedPreviewID == nil)
        #expect(fixture.state.navigation.section == .previews)
        #expect(fixture.model.recentPreviews.count == 3)
    }

    @Test func scrolling_to_the_end_loads_the_next_page_without_a_load_more_button() async throws {
        let fixture = try await makeFixture(previewCount: 20, hasNextPage: true)
        given(fixture.previews).listPreviews(
            displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
            page: .value(2), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
        ).willReturn(.test(
            previews: (21 ... 40).map { .test(id: "preview-\($0)", displayName: "Sample App \($0)") },
            paginationMetadata: .test(hasNextPage: true, currentPage: 2)
        ))
        given(fixture.previews).listPreviews(
            displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
            page: .value(3), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
        ).willReturn(.test(
            previews: [.test(id: "last-page", displayName: "Sample App 41")],
            paginationMetadata: .test(hasNextPage: false, currentPage: 3)
        ))
        fixture.state.navigation.section = .previews
        let window = makeWindow(fixture: fixture, width: 1280)
        window.orderFront(nil)
        defer { window.close() }
        let tables = try await renderedTables(in: window, expectedCount: 2)
        let browser = try #require(tables.first { $0.numberOfRows >= 20 })
        #expect(fixture.model.previews.count == 20)

        browser.scrollRowToVisible(browser.numberOfRows - 1)
        for _ in 0 ..< 100 where fixture.model.previews.count == 20 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(fixture.model.previews.count == 40)
        #expect(fixture.model.hasMorePreviews)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.model.previews.count == 40)

        browser.scrollRowToVisible(browser.numberOfRows - 1)
        for _ in 0 ..< 100 where fixture.model.previews.count == 40 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fixture.model.previews.count == 41)
        #expect(!fixture.model.hasMorePreviews)
        #expect(fixture.model.paginationErrorMessage == nil)
        #expect(descendants(of: NSButton.self, in: window.contentView!).allSatisfy { $0.title != "Load More" })
    }

    @Test func filters_with_no_loaded_matches_continue_to_the_next_page() async throws {
        let fixture = try await makeFixture(previewCount: 20, hasNextPage: true)
        given(fixture.previews).listPreviews(
            displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
            page: .value(2), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
        ).willReturn(.test(
            previews: [.test(id: "next-page", displayName: "Only on next page")],
            paginationMetadata: .test(hasNextPage: false, currentPage: 2)
        ))
        fixture.state.navigation.section = .previews
        fixture.model.searchText = "Only on next page"
        let window = makeWindow(fixture: fixture, width: 1280)
        defer { window.close() }
        _ = try await renderedTables(in: window, expectedCount: 2)
        for _ in 0 ..< 100 where fixture.model.filteredPreviews.isEmpty {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(fixture.model.filteredPreviews.map(\.id) == ["next-page"])
        #expect(fixture.model.recentPreviews.map(\.id) == ["preview-1", "preview-2", "preview-3"])
        #expect(!fixture.model.hasMorePreviews)
    }

    private func makeFixture(previewCount: Int = 5, hasNextPage: Bool = false) async throws -> Fixture {
        let projects = MockListProjectsServicing()
        let previews = MockListPreviewsServicing()
        let environment = MockServerEnvironmentServicing()
        let storage = MockAppStoring()
        given(projects).listProjects(serverURL: .any).willReturn([
            .test(fullName: "sample/project"), .test(fullName: "sample/other"),
        ])
        given(environment).url().willReturn(URL(string: "https://example.invalid")!)
        given(storage).get(.any as Parameter<ProjectSelectionsKey.Type>).willReturn([:])
        given(storage).set(.any as Parameter<ProjectSelectionsKey.Type>, value: .any).willReturn()
        given(storage).get(.any as Parameter<RecentProjectsKey.Type>).willReturn([:])
        given(storage).set(.any as Parameter<RecentProjectsKey.Type>, value: .any).willReturn()
        var samplePreviews: [ServerPreview] = []
        for index in 1 ... previewCount {
            let branch = index == 1 ? "main" : "feature/native-desktop-overview"
            let track: String? = index == 1 ? "beta" : nil
            let insertedAt = Date().addingTimeInterval(-Double(index) * 3600)
            let preview = ServerPreview.test(
                id: "preview-\(index)", iconURL: URL(fileURLWithPath: "/dev/null"),
                displayName: "Sample App \(index)", gitCommitSHA: "abc1234",
                gitBranch: branch, track: track, insertedAt: insertedAt
            )
            samplePreviews.append(preview)
        }
        given(previews)
            .listPreviews(
                displayName: .any, specifier: .any, track: .any, supportedPlatforms: .any,
                page: .value(1), pageSize: .any, distinctField: .any, fullHandle: .any, serverURL: .any
            )
            .willReturn(.test(
                previews: samplePreviews,
                paginationMetadata: .test(hasNextPage: hasNextPage, currentPage: 1)
            ))
        let context = ProjectContext(
            scope: "workspace-test", listProjectsService: projects,
            serverEnvironmentService: environment, appStorage: storage
        )
        let model = DesktopPreviewsModel(
            projectContext: context, listPreviewsService: previews, serverEnvironmentService: environment
        )
        try await model.refresh()
        return Fixture(model: model, state: WorkspaceState(), previews: previews)
    }

    private func makeWindow(fixture: Fixture, width: Double) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 680),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: DesktopWorkspaceView(
            accountHandle: "sample-user", model: fixture.model,
            navigation: Binding(get: { fixture.state.navigation }, set: { fixture.state.navigation = $0 }),
            refresh: {}, loadMore: { await fixture.model.loadMore() }
        )
        .environmentObject(DeviceService(taskStatusReporter: TaskStatusReporter(), appStorage: MockAppStoring()))
        .environmentObject(ErrorHandling())
        .preferredColorScheme(.light))
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func renderedTables(in window: NSWindow, expectedCount: Int) async throws -> [NSTableView] {
        let content = try #require(window.contentView)
        for _ in 0 ..< 100 {
            content.layoutSubtreeIfNeeded()
            let tables = descendants(of: NSTableView.self, in: content)
            if tables.count == expectedCount, tables.allSatisfy({ $0.frame.width > 0 }) {
                try await Task.sleep(for: .milliseconds(50))
                return tables
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let tables = descendants(of: NSTableView.self, in: content)
        try #require(tables.count == expectedCount)
        return tables
    }

    private func recordScreenshot(of window: NSWindow, named name: String) {
        guard let content = window.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)
        else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        Attachment.record(Array(png), named: name)
    }

    private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private struct Fixture {
        let model: DesktopPreviewsModel
        let state: WorkspaceState
        let previews: MockListPreviewsServicing
    }
}

@MainActor
@Observable
private final class WorkspaceState {
    var navigation = DesktopNavigation()
}
