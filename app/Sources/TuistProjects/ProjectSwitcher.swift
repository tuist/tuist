import SwiftUI
import TuistServer

public struct ProjectSwitcher: View {
    private let context: ProjectContext
    @State private var isPresented = false

    public init(context: ProjectContext) {
        self.context = context
    }

    public var body: some View {
        Group {
            #if os(macOS)
                Button { isPresented = true } label: { switcherLabel }
                    .buttonStyle(.plain)
                    .help("Switch Project")
                    .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                        MacProjectPicker(context: context) { isPresented = false }
                    }
            #else
                Menu {
                    ForEach(context.switcherProjects, id: \.fullName) { project in
                        Button {
                            context.selectProject(project.fullName)
                        } label: {
                            if project.fullName == context.selectedFullHandle {
                                Label(project.fullName, systemImage: "checkmark")
                            } else {
                                Text(project.fullName)
                            }
                        }
                        .accessibilityIdentifier("quick-project-\(project.fullName)")
                    }
                    Divider()
                    Button("Switch project…", systemImage: "arrow.left.arrow.right") { isPresented = true }
                } label: {
                    switcherLabel
                }
                .menuOrder(.fixed)
                .buttonStyle(.borderless)
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
                .sheet(isPresented: $isPresented) {
                    NavigationStack {
                        ProjectPicker(context: context) { isPresented = false }
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close", systemImage: "xmark") { isPresented = false }
                                }
                            }
                    }
                    .presentationDragIndicator(.visible)
                }
            #endif
        }
        .accessibilityLabel("Project: \(context.selectedFullHandle ?? "None selected")")
        .accessibilityIdentifier("project-switcher")
        .accessibilityHint("Switch the project for Home and Previews")
    }

    private var switcherLabel: some View {
        HStack(spacing: 8) {
            #if os(macOS)
                Image(systemName: "square.stack.3d.up")
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.selectedFullHandle?.split(separator: "/").last.map(String.init) ?? "Choose a project")
                        .font(.headline)
                    if let organization = context.selectedFullHandle?.split(separator: "/").first {
                        Text(String(organization))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            #else
                Text(context.selectedFullHandle ?? "Choose a project")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            #endif
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .lineLimit(1)
        #if os(iOS)
            .padding(.horizontal, 8)
        #endif
            .contentShape(Rectangle())
    }
}

private struct ProjectPicker: View {
    let context: ProjectContext
    let onSelection: () -> Void
    @State private var search = ""

    private var sections: [ProjectPickerSection] {
        ProjectPickerSection.make(projects: context.projects, recentProjects: context.recentProjects, search: search)
    }

    var body: some View {
        List {
            if let error = context.errorMessage {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { try? await context.refresh() }
                    }
                }
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.projects, id: \.fullName) { project in
                        row(project, showsOrganization: section.isRecent)
                    }
                }
            }
        }
        .overlay {
            if context.isLoading, context.projects.isEmpty {
                ProgressView("Loading projects…")
            } else if context.projects.isEmpty, context.errorMessage == nil {
                ContentUnavailableView("No Projects", systemImage: "folder")
            } else if !search.isEmpty, sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("Switch Project")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .searchable(text: $search, prompt: "Search projects")
            .refreshable { try? await context.refresh() }
            .task { try? await context.load() }
    }

    private func row(_ project: ServerProject, showsOrganization: Bool) -> some View {
        Button {
            context.selectProject(project.fullName)
            onSelection()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.fullName.split(separator: "/").last.map(String.init) ?? project.fullName)
                        .foregroundStyle(.primary)
                    if showsOrganization {
                        Text(project.fullName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if context.selectedFullHandle == project.fullName {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("project-\(project.fullName)")
    }
}
