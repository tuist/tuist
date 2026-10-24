import CoreTransferable
import ImageIO
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct AtlasAttachmentFile: Sendable {
    static let maximumBytes = 5 * 1024 * 1024
    let filename: String
    let contentType: String
    let data: Data

    static func read(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw Failure.size
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumBytes else { throw Failure.size }
        return Self(filename: safeName(url.lastPathComponent),
                    contentType: values.contentType?.preferredMIMEType ?? "application/octet-stream", data: data)
    }

    static func photo(_ url: URL) throws -> Self {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw Failure.image }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.image
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length > 0, data.length <= maximumBytes else { throw Failure.size }
        return Self(filename: "Photo.jpg", contentType: "image/jpeg", data: data as Data)
    }

    static func safeName(_ value: String) -> String {
        var name = String(String.UnicodeScalarView(value.unicodeScalars.filter {
            ![.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
                && $0 != "/" && $0 != "\\"
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.utf8.count > 240 { name.removeLast() }
        return name.isEmpty || name == "." || name == ".." ? "Attachment" : name
    }

    static func preview(_ data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        let file = directory.appendingPathComponent(safeName(filename), isDirectory: false)
        do {
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    enum Failure: LocalizedError {
        case size
        case image
        var errorDescription: String? {
            switch self {
            case .size: "Choose a nonempty file up to 5 MB."
            case .image: "This photo could not be read. Choose another image."
            }
        }
    }
}

private struct AtlasPickedPhoto: Transferable {
    let file: AtlasAttachmentFile
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            Self(file: try AtlasAttachmentFile.photo(received.file))
        }
    }
}

struct AtlasAttachmentPicker: ViewModifier {
    @Binding var photosPresented: Bool
    @Binding var filesPresented: Bool
    let upload: (AtlasAttachmentFile) async -> Void
    let failure: (String) -> Void
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $photosPresented, selection: $photos, maxSelectionCount: 4, matching: .images)
            .onChange(of: photos) { _, selected in
                importing?.cancel()
                importing = Task {
                    for item in selected {
                        do {
                            guard let photo = try await item.loadTransferable(type: AtlasPickedPhoto.self) else {
                                throw AtlasAttachmentFile.Failure.image
                            }
                            try Task.checkCancellation()
                            await upload(photo.file)
                        } catch is CancellationError { return } catch { failure(error.localizedDescription) }
                    }
                    photos = []
                }
            }
            .fileImporter(isPresented: $filesPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    importing?.cancel()
                    importing = Task {
                        for url in urls.prefix(4) {
                            do {
                                let file = try await Task.detached { try AtlasAttachmentFile.read(url) }.value
                                try Task.checkCancellation()
                                await upload(file)
                            } catch is CancellationError { return } catch { failure(error.localizedDescription) }
                        }
                    }
                case .failure(let error): failure(error.localizedDescription)
                }
            }
            .onDisappear { importing?.cancel() }
    }
}

struct AtlasDraftAttachments: View {
    @ObservedObject var model: AtlasOrbit
    let open: (AtlasThreadAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.draftAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.draftAttachments) { attachment in
                            AtlasAttachmentChip(attachment: attachment, open: { open(attachment) }, remove: {
                                Task { await model.removeAttachment(attachment) }
                            }).frame(width: 240)
                        }
                    }
                }
            }
            if let name = model.pendingUploadName {
                Text("Upload needs attention: \(name)").font(.caption).lineLimit(2)
                HStack {
                    Button("Retry upload") { Task { await model.resolveUpload(retry: true) } }
                    Button("Discard upload", role: .destructive) { Task { await model.resolveUpload(retry: false) } }
                }.buttonStyle(.borderless).frame(minHeight: 44)
            }
            if model.attachmentBusy { ProgressView("Updating attachments…").font(.caption) }
        }
        .disabled(model.saving || model.attachmentBusy)
    }
}

struct AtlasAttachmentChip: View {
    let attachment: AtlasThreadAttachment
    let open: () -> Void
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteSize), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: attachment.contentType.hasPrefix("image/") ? "photo" : "doc")
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a protected copy of this attachment.")
            if let remove {
                Button("Remove \(attachment.filename)", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly).frame(width: 44, height: 44).buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("thread-attachment-\(attachment.id)")
    }
}

struct AtlasAttachmentPreview: ViewModifier {
    @Binding var url: URL?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { url != nil }, set: { if !$0 { url = nil } })) {
                if let file = url {
                    NavigationStack {
                        AtlasAttachmentQuickLook(url: file)
                            .navigationTitle(file.lastPathComponent).navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { url = nil } } }
                    }
                }
            }
            .onChange(of: url) { previous, current in
                if let previous, previous != current { try? FileManager.default.removeItem(at: previous.deletingLastPathComponent()) }
            }
            .onDisappear {
                if let url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                url = nil
            }
    }
}

private struct AtlasAttachmentQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
