#if os(macOS)
    import AppKit
    import SwiftUI
    import TuistServer

    struct MacProjectPicker: View {
        let context: ProjectContext
        let onSelection: () -> Void
        @State private var search = ""
        @State private var highlightedProject: String?

        private var sections: [ProjectPickerSection] {
            ProjectPickerSection.make(projects: context.projects, recentProjects: context.recentProjects, search: search)
        }

        private var listHeight: CGFloat {
            let rowCount = sections.reduce(0) { $0 + $1.projects.count }
            let sectionSpacing = max(0, sections.count - 1) * 20
            return min(360, max(140, CGFloat(rowCount * 48 + sections.count * 28 + sectionSpacing + 20)))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Projects")
                    .font(.headline)
                    .padding(12)
                ProjectSearchField(text: $search, onSubmit: confirmSelection)
                    .frame(height: 24)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                Divider()
                if let error = context.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try Again") { Task { try? await context.refresh() } }
                    }
                    .padding(12)
                }
                List(selection: $highlightedProject) {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.projects, id: \.fullName) { project in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.fullName.split(separator: "/").last.map(String.init) ?? project.fullName)
                                            .lineLimit(1)
                                        Text(project.fullName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .opacity(context.selectedFullHandle == project.fullName ? 1 : 0)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .tag(project.fullName)
                                .onTapGesture { select(project.fullName) }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("project-\(project.fullName)")
                                .accessibilityAddTraits(context.selectedFullHandle == project.fullName ? [.isSelected] : [])
                                .accessibilityAction { select(project.fullName) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(height: listHeight)
                .onKeyPress(.return) {
                    confirmSelection()
                    return .handled
                }
                .overlay {
                    if context.isLoading, context.projects.isEmpty {
                        ProgressView("Loading projects…")
                    } else if sections.isEmpty, context.errorMessage == nil {
                        ContentUnavailableView(
                            search.isEmpty ? "No Projects" : "No Matching Projects",
                            systemImage: "folder"
                        )
                    }
                }
            }
            .frame(width: 340)
            .onAppear { highlightedProject = context.selectedFullHandle }
            .onChange(of: search) { highlightedProject = sections.first?.projects.first?.fullName }
            .task { try? await context.load() }
        }

        private func confirmSelection() {
            guard let highlightedProject else { return }
            select(highlightedProject)
        }

        private func select(_ fullHandle: String) {
            context.selectProject(fullHandle)
            onSelection()
        }
    }

    private struct ProjectSearchField: NSViewRepresentable {
        @Binding var text: String
        let onSubmit: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeNSView(context: Context) -> NSSearchField {
            let field = NSSearchField(string: text)
            field.placeholderString = "Search projects"
            field.setAccessibilityLabel("Search projects")
            field.setAccessibilityIdentifier("project-search-field")
            field.delegate = context.coordinator
            field.sendsSearchStringImmediately = true
            return field
        }

        func updateNSView(_ field: NSSearchField, context: Context) {
            context.coordinator.parent = self
            if field.stringValue != text { field.stringValue = text }
        }

        final class Coordinator: NSObject, NSSearchFieldDelegate {
            var parent: ProjectSearchField

            init(_ parent: ProjectSearchField) { self.parent = parent }

            func controlTextDidChange(_ notification: Notification) {
                guard let field = notification.object as? NSSearchField else { return }
                parent.text = field.stringValue
            }

            func control(_: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
                guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
                parent.onSubmit()
                return true
            }
        }
    }
#endif
