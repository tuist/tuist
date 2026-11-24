import Foundation
import ImageIO
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct PromptAttachment: Decodable, Identifiable, Sendable {
    var id = UUID()
    let name: String
    let mime_type: String
    let data_base64: String

    private enum CodingKeys: String, CodingKey { case name, mime_type, data_base64 }

    var payload: [String: String] {
        ["name": name, "mime_type": mime_type, "data_base64": data_base64]
    }

    static func read(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Read one byte beyond the limit, never an unbounded security-scoped file.
        let bytes = try handle.read(upToCount: 1_048_577) ?? Data()
        guard !bytes.isEmpty, bytes.count <= 1_048_576 else {
            throw AppClientError(message: String(localized: "Files must be between 1 byte and 1 MiB."))
        }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return Self(name: url.lastPathComponent, mime_type: type, data_base64: bytes.base64EncodedString())
    }

    /// Photo-library images are normalized without decoding their full-resolution pixels.
    static func photo(_ bytes: Data) throws -> Self {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1600,
              ] as CFDictionary)
        else { throw AppClientError(message: String(localized: "Could not read this image.")) }
        for quality in [0.8, 0.6, 0.4] {
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                if CGImageDestinationFinalize(destination), data.length <= 1_048_576 {
                    return Self(name: "Photo-\(UUID().uuidString.prefix(8)).jpg", mime_type: "image/jpeg", data_base64: (data as Data).base64EncodedString())
                }
            }
        }
        throw AppClientError(message: String(localized: "This image is too large. Choose a smaller image."))
    }
}

/// The same bounded thumbnail is used for picked and received images.
struct AttachmentLabel: View {
    let file: PromptAttachment

    var body: some View {
        HStack(spacing: 8) {
            if file.mime_type.hasPrefix("image/"),
               let bytes = Data(base64Encoded: file.data_base64),
               let source = CGImageSourceCreateWithData(bytes as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: 120,
               ] as CFDictionary)
            {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc").frame(width: 40, height: 40).accessibilityHidden(true)
            }
            Text(verbatim: file.name).font(.callout).lineLimit(2).truncationMode(.middle)
        }
        .foregroundStyle(Noora.labelPrimary)
        .frame(minHeight: 44)
    }
}

struct MessageAttachments: View {
    let files: [PromptAttachment]
    @State private var preview: URL?
    @State private var directory: URL?
    @State private var error: String?

    var body: some View {
        ForEach(files) { file in
            Button {
                do {
                    cleanup()
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    directory = folder
                    // Never let a server-supplied filename escape the private directory.
                    let url = folder.appendingPathComponent(URL(fileURLWithPath: file.name).lastPathComponent)
                    guard let bytes = Data(base64Encoded: file.data_base64) else { return }
                    try bytes.write(to: url, options: .atomic)
                    #if os(iOS)
                        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
                    #endif
                    preview = url
                } catch { self.error = error.localizedDescription }
            } label: { AttachmentLabel(file: file).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint("Preview attachment")
        }
        .quickLookPreview($preview)
        .onChange(of: preview) { _, url in if url == nil { cleanup() } }
        .onDisappear { preview = nil; cleanup() }
        if let error { Text(verbatim: error).font(.caption).foregroundStyle(Noora.labelDestructive) }
    }

    private func cleanup() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}
