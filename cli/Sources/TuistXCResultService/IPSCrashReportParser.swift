import Foundation

public struct IPSCrashReportParser {
    public init() {}

    public func triggeredThreadFrames(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.count >= 2,
              let payloadData = lines[1].data(using: .utf8),
              let payload = try? JSONDecoder().decode(IPSPayload.self, from: payloadData)
        else { return nil }

        let imageNames = payload.usedImages.map { image in
            image.name ?? image.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "???"
        }

        let thread = payload.threads.first { $0.triggered == true } ?? payload.threads.first
        guard let frames = thread?.frames, !frames.isEmpty else { return nil }

        let parsed = frames.enumerated().map { index, frame in
            let imageIndex = frame.imageIndex ?? 0
            let imageName = imageIndex < imageNames.count ? imageNames[imageIndex] : "???"
            return (index: index, imageName: imageName, symbol: formatSymbol(frame))
        }

        let maxIndexWidth = String(parsed.count - 1).count
        let maxImageWidth = parsed.map(\.imageName.count).max() ?? 0

        return parsed.map { frame in
            let indexStr = String(frame.index).padding(toLength: maxIndexWidth, withPad: " ", startingAt: 0)
            let imageStr = frame.imageName.padding(toLength: maxImageWidth, withPad: " ", startingAt: 0)
            return "\(indexStr)  \(imageStr)  \(frame.symbol)"
        }.joined(separator: "\n")
    }

    private func formatSymbol(_ frame: IPSFrame) -> String {
        let offset = frame.imageOffset ?? 0
        guard let symbol = frame.symbol else {
            return "0x\(String(offset, radix: 16))"
        }
        if let sourceFile = frame.sourceFile, let sourceLine = frame.sourceLine {
            let fileName = URL(fileURLWithPath: sourceFile).lastPathComponent
            return "\(symbol) (\(fileName):\(sourceLine)) + \(offset)"
        }
        return "\(symbol) + \(offset)"
    }
}

private struct IPSPayload: Decodable {
    let usedImages: [IPSImage]
    let threads: [IPSThread]
}

private struct IPSImage: Decodable {
    let name: String?
    let path: String?
}

private struct IPSThread: Decodable {
    let triggered: Bool?
    let frames: [IPSFrame]?
}

private struct IPSFrame: Decodable {
    let imageIndex: Int?
    let symbol: String?
    let imageOffset: Int?
    let sourceFile: String?
    let sourceLine: Int?
}
