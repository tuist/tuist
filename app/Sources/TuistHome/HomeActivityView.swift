import SwiftUI

public struct HomeActivityView: View {
    private let model: HomeActivityModel
    private let handleAuthenticationError: (Error) -> Void

    public init(model: HomeActivityModel, handleAuthenticationError: @escaping (Error) -> Void) {
        self.model = model
        self.handleAuthenticationError = handleAuthenticationError
    }

    public var body: some View {
        Group {
            if model.projectContext.selectedFullHandle != nil {
                if let message = sharedError {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Build and test activity").font(.headline)
                        Text(message).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await model.load(force: true) } }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(HomeActivityKind.allCases, id: \.self) { kind in
                            activityCard(kind)
                        }
                    }
                }
            }
        }
        .task(id: model.projectContext.selectedFullHandle) { await model.load() }
        .onChange(of: model.authenticationError != nil, initial: true) {
            if let error = model.authenticationError { handleAuthenticationError(error) }
        }
    }

    private var columns: [GridItem] {
        #if os(macOS)
            [GridItem(.adaptive(minimum: 250), alignment: .top)]
        #else
            [GridItem(.flexible())]
        #endif
    }

    private var sharedError: String? {
        let sections = HomeActivityKind.allCases.map { model.section($0) }
        let errors = sections.compactMap(\.errorMessage)
        guard errors.count == sections.count, Set(errors).count == 1, sections.allSatisfy(\.items.isEmpty) else {
            return nil
        }
        return errors.first
    }

    private func activityCard(_ kind: HomeActivityKind) -> some View {
        let section = model.section(kind)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind == .flakyTests ? Color.orange : .red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.headline)
                        .accessibilityIdentifier("home-activity-heading-\(kind.rawValue)")
                    Text("Last 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if section.isLoading, section.hasLoaded { ProgressView().controlSize(.small) }
            }
            .padding(16)

            ForEach(section.items) { item in
                Divider().padding(.horizontal, 16)
                HStack(spacing: 12) {
                    Link(destination: item.url) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Text(item.occurredAt, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(item.title)\nOpen details in your browser")
                    .accessibilityHint("Opens details in your browser")
                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                        #if os(iOS)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        #endif
                    }
                    .buttonStyle(.borderless)
                    .help("Share link")
                    .accessibilityLabel("Share \(item.title)")
                }
                .padding(16)
            }

            if let message = section.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await model.retry(kind) } }
                        .accessibilityIdentifier("retry-home-\(kind.rawValue)")
                }
                .padding(16)
            } else if section.items.isEmpty {
                if section.isLoading || !section.hasLoaded {
                    ProgressView("Loading activity…")
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    Text(kind.emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
