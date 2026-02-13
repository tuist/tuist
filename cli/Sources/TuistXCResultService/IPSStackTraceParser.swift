import Foundation

public struct IPSStackTraceParser {
    public init() {}

    public func triggeredThreadFrames(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return nil }

        guard let payloadData = lines[1].data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }

        guard let usedImages = payload["usedImages"] as? [[String: Any]],
              let threads = payload["threads"] as? [[String: Any]]
        else { return nil }

        let imageNames = usedImages.map { image in
            (image["name"] as? String) ?? (image["path"] as? String).map { ($0 as NSString).lastPathComponent } ?? "???"
        }

        guard let triggeredThread = threads.first(where: { ($0["triggered"] as? Bool) == true }) ?? threads.first
        else { return nil }

        guard let frames = triggeredThread["frames"] as? [[String: Any]] else { return nil }

        var parsedFrames: [(index: Int, imageName: String, symbol: String)] = []

        for (index, frame) in frames.enumerated() {
            let imageIndex = frame["imageIndex"] as? Int ?? 0
            let imageName = imageIndex < imageNames.count ? imageNames[imageIndex] : "???"

            var symbolPart: String
            if let symbol = frame["symbol"] as? String {
                let offset = frame["imageOffset"] as? Int ?? 0
                if let sourceFile = frame["sourceFile"] as? String,
                   let sourceLine = frame["sourceLine"] as? Int
                {
                    let fileName = (sourceFile as NSString).lastPathComponent
                    symbolPart = "\(symbol) (\(fileName):\(sourceLine)) + \(offset)"
                } else {
                    symbolPart = "\(symbol) + \(offset)"
                }
            } else {
                let offset = frame["imageOffset"] as? Int ?? 0
                symbolPart = "0x\(String(offset, radix: 16))"
            }

            parsedFrames.append((index: index, imageName: imageName, symbol: symbolPart))
        }

        guard !parsedFrames.isEmpty else { return nil }

        let maxIndexWidth = String(parsedFrames.last?.index ?? 0).count
        let maxImageWidth = parsedFrames.map(\.imageName.count).max() ?? 0

        let outputLines = parsedFrames.map { frame in
            let indexStr = String(frame.index).padding(toLength: maxIndexWidth, withPad: " ", startingAt: 0)
            let imageStr = frame.imageName.padding(toLength: maxImageWidth, withPad: " ", startingAt: 0)
            return "\(indexStr)  \(imageStr)  \(frame.symbol)"
        }

        return outputLines.joined(separator: "\n")
    }
}
