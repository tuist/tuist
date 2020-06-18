import Foundation
import TuistCore

public protocol SettingsContentHashing {
    func hash(settings: Settings) throws -> String
}

/// `SettingsContentHasher`
/// is responsible for computing a hash that uniquely identifies some `Settings`
public final class SettingsContentHasher: SettingsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - InfoPlistContentHashing

    public func hash(settings _: Settings) throws -> String {
        ""
    }
}
