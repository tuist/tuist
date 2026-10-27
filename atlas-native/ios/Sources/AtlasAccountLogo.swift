import ImageIO
import SwiftUI

struct AtlasAccountLogo: View {
    let item: AtlasBusinessRecord

    private var url: URL? {
        guard !item["primary_domain"].isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")!
        components.queryItems = [URLQueryItem(name: "domain", value: item["primary_domain"]), URLQueryItem(name: "sz", value: "128")]
        return components.url
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return AtlasCertificateTrust.makeSession(configuration: configuration)
    }()

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Text(String(item["name"].prefix(1)).uppercased()).font(.headline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
            }
        }
        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: item["primary_domain"]) {
            image = nil
            guard let url else { return }
            do {
                let loaded = try await Self.loadImage(from: url)
                guard !Task.isCancelled else { return }
                image = loaded
            } catch {
                // Keep the local placeholder; never retry with an unprotected transport.
            }
        }
    }

    private nonisolated static func loadImage(from url: URL) async throws -> CGImage? {
        let (stream, response) = try await session.bytes(from: url)
        defer { stream.task.cancel() }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= 256 * 1024
        else { return nil }
        var data = Data()
        for try await byte in stream {
            guard data.count < 256 * 1024 else { return nil }
            data.append(byte)
        }
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...512).contains(width), (1...512).contains(height)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ] as CFDictionary)
    }
}
