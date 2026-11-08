import Foundation

struct AtlasShareRecipient: Codable, Equatable {
    let id: UUID
    let server: URL
}

struct AtlasShareCapture: Codable, Identifiable {
    let id: UUID
    let recipient: AtlasShareRecipient
    let createdAt: Date
    var url: String
    var content: String
    var title: String
    var description: String
    var tags: [String]
    // Freeze the reviewed payload before the first network attempt, including an uncertain save.
    var submitted: Bool = false

    var attributes: [String: Any] {
        ["title": title, "url": url, "content": content, "description": description, "tags": tags]
    }
}

enum AtlasShareError: LocalizedError {
    case unavailable, signedOut, unsupported, tooLarge, full

    var errorDescription: String? {
        switch self {
        case .unavailable: "The Atlas share inbox is unavailable. Open Atlas and try again."
        case .signedOut: "Open Atlas and sign in before sharing."
        case .unsupported: "Share one public HTTPS link or some text. Local images, videos and files are not supported yet."
        case .tooLarge: "Share a link up to 2,048 characters or text up to 20,000 characters."
        case .full: "Your Atlas inbox is full. Open Atlas to review your saved shares."
        }
    }
}

struct AtlasShareInbox {
    static let group = "group.dev.tuist.atlas.share"
    let directory: URL

    static func shared() throws -> Self {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw AtlasShareError.unavailable
        }
        return Self(directory: container.appendingPathComponent("MoodboardInbox", isDirectory: true))
    }

    func recipient() throws -> AtlasShareRecipient {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("recipient.json")),
              let value = try? JSONDecoder().decode(AtlasShareRecipient.self, from: data) else {
            throw AtlasShareError.signedOut
        }
        return value
    }

    func configure(_ recipient: AtlasShareRecipient?) throws {
        try prepare()
        let path = directory.appendingPathComponent("recipient.json")
        if let recipient {
            try write(recipient, to: path)
        } else if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        for file in try files() {
            let capture = try? JSONDecoder().decode(AtlasShareCapture.self, from: Data(contentsOf: file))
            if capture?.recipient != recipient {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    func captures(for recipient: AtlasShareRecipient) throws -> [AtlasShareCapture] {
        guard try self.recipient() == recipient else { throw AtlasShareError.signedOut }
        return try files().compactMap { file in
            let data = try Data(contentsOf: file)
            guard data.count <= 128 * 1024 else { throw AtlasShareError.tooLarge }
            let capture = try JSONDecoder().decode(AtlasShareCapture.self, from: data)
            return capture.recipient == recipient ? capture : nil
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func enqueue(url: String, content: String, recipient: AtlasShareRecipient,
                 title: String = "", description: String = "") throws {
        guard try self.recipient() == recipient else { throw AtlasShareError.signedOut }
        try Self.validate(url: url, content: content)
        guard try files().count < 100 else { throw AtlasShareError.full }
        let capture = AtlasShareCapture(id: UUID(), recipient: recipient, createdAt: Date(), url: url,
                                        content: content, title: String(title.prefix(200)),
                                        description: String(description.prefix(2000)), tags: [])
        try save(capture)
    }

    func save(_ capture: AtlasShareCapture) throws {
        guard try recipient() == capture.recipient else { throw AtlasShareError.signedOut }
        try Self.validate(url: capture.url, content: capture.content)
        try write(capture, to: path(capture.id))
    }

    func remove(_ id: UUID) throws { try FileManager.default.removeItem(at: path(id)) }

    static func validate(url: String, content: String) throws {
        guard url.unicodeScalars.count <= 2048, content.unicodeScalars.count <= 20_000 else { throw AtlasShareError.tooLarge }
        guard !url.contains("\0"), !content.contains("\0") else { throw AtlasShareError.unsupported }
        if !url.isEmpty {
            guard let components = URLComponents(string: url), components.scheme == "https",
                  components.host != nil, components.user == nil, components.password == nil,
                  components.port == nil || components.port == 443 else { throw AtlasShareError.unsupported }
        } else if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AtlasShareError.unsupported
        }
    }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private func files() throws -> [URL] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
    }

    private func path(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private func write(_ value: some Encodable, to path: URL) throws {
        try prepare()
        let data = try JSONEncoder().encode(value)
        guard data.count <= 128 * 1024 else { throw AtlasShareError.tooLarge }
        try data.write(to: path, options: [.atomic, .completeFileProtection])
    }
}
