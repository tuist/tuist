import AppKit
import Foundation
import Mockable
import SwiftUI
import Testing
import TuistAppStorage
import TuistServer

@testable import TuistProjects

@MainActor
struct DesktopProjectPickerTests {
    @Test func native_search_is_visible_and_the_project_list_fits_its_content() async throws {
        let context = try await makeContext()
        let window = makeWindow(context: context)
        defer { window.close() }
        let list = try await renderedList(in: window, expectedRows: 6)
        let content = try #require(window.contentView)
        let search = try #require(descendants(of: NSSearchField.self, in: content).first)

        #expect(search.placeholderString == "Search projects")
        #expect(search.accessibilityIdentifier() == "project-search-field")
        #expect(search.frame.width > 0)
        #expect(list.numberOfRows == 6)
        let visibleHeight = try #require(list.enclosingScrollView?.contentView.bounds.height)
        #expect(list.rect(ofRow: list.numberOfRows - 1).maxY <= visibleHeight)
    }

    @Test func native_search_filters_projects_and_return_confirms_the_result() async throws {
        let context = try await makeContext()
        var selections = 0
        let window = makeWindow(context: context) { selections += 1 }
        defer { window.close() }
        _ = try await renderedList(in: window, expectedRows: 6)
        let content = try #require(window.contentView)
        let search = try #require(descendants(of: NSSearchField.self, in: content).first)
        search.stringValue = "shop"
        search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
        _ = try await renderedList(in: window, expectedRows: 2)
        let handled = search.delegate?.control?(
            search,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        #expect(handled == true)
        #expect(context.selectedFullHandle == "acme/shop")
        #expect(selections == 1)
    }

    private func makeContext() async throws -> ProjectContext {
        let service = MockListProjectsServicing()
        let environment = MockServerEnvironmentServicing()
        let storage = MockAppStoring()
        given(service).listProjects(serverURL: .any).willReturn([
            .test(id: 1, fullName: "tuist/tuist"),
            .test(id: 2, fullName: "tuist/noora"),
            .test(id: 3, fullName: "acme/shop"),
        ])
        given(environment).url().willReturn(URL(string: "https://tuist.dev")!)
        given(storage).get(.any as Parameter<ProjectSelectionsKey.Type>).willReturn([:])
        given(storage).get(.any as Parameter<RecentProjectsKey.Type>).willReturn([:])
        given(storage).set(.any as Parameter<ProjectSelectionsKey.Type>, value: .any).willReturn()
        given(storage).set(.any as Parameter<RecentProjectsKey.Type>, value: .any).willReturn()
        let context = ProjectContext(
            scope: "picker-test",
            listProjectsService: service,
            serverEnvironmentService: environment,
            appStorage: storage
        )
        try await context.load()
        return context
    }

    private func makeWindow(context: ProjectContext, onSelection: @escaping () -> Void = {}) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MacProjectPicker(context: context, onSelection: onSelection))
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func renderedList(in window: NSWindow, expectedRows: Int) async throws -> NSTableView {
        let content = try #require(window.contentView)
        for _ in 0 ..< 100 {
            content.layoutSubtreeIfNeeded()
            if let list = descendants(of: NSTableView.self, in: content).first, list.numberOfRows == expectedRows {
                return list
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let list = try #require(descendants(of: NSTableView.self, in: content).first)
        try #require(list.numberOfRows == expectedRows)
        return list
    }

    private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }
}
