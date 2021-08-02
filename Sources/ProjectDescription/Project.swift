import Foundation

// MARK: - Project

/// Project is similar to what you specify in `.xcodeproj`
public struct Project: Codable, Equatable {
    /// Name of the project
    public let name: String
    /// Organization name to be used for the project
    public let organizationName: String?
    /// Additional project options
    public let options: [Options]
    /// Project Swift packages
    public let packages: [Package]
    /// Project targets
    public let targets: [Target]
    /// Project schemes
    public let schemes: [Scheme]
    /// Project settings
    public let settings: Settings?
    /// Customizable file header template for Xcode built-in file templates
    public let fileHeaderTemplate: FileHeaderTemplate?
    /// The additional files to include in the project (won't be included in a build phase)
    public let additionalFiles: [FileElement]
    /// Resource synthesizers create type-safe accessors for your resources
    public let resourceSynthesizers: [ResourceSynthesizer]

    public init(
        name: String,
        organizationName: String? = nil,
        options: [Options] = [],
        packages: [Package] = [],
        settings: Settings? = nil,
        targets: [Target] = [],
        schemes: [Scheme] = [],
        fileHeaderTemplate: FileHeaderTemplate? = nil,
        additionalFiles: [FileElement] = [],
        resourceSynthesizers: [ResourceSynthesizer] = .default
    ) {
        self.name = name
        self.organizationName = organizationName
        self.options = options
        self.packages = packages
        self.targets = targets
        self.schemes = schemes
        self.settings = settings
        self.additionalFiles = additionalFiles
        self.fileHeaderTemplate = fileHeaderTemplate
        self.resourceSynthesizers = resourceSynthesizers
        dumpIfNeeded(self)
    }
}

// MARK: - Options

extension Project {
    /// Additional options related to the `Project`
    public enum Options: Codable, Equatable {
        /// Text settings to override user ones for currecnt project
        case textSettings(TextSettings)
    }
}

// MARK: - TextSettings

extension Project.Options {
    /// Text settings for Xcode project
    public struct TextSettings: Codable, Equatable {
        /// Use tabs over spaces
        public let usesTabs: Bool?
        /// Indent width
        public let indentWidth: UInt?
        /// Tab width
        public let tabWidth: UInt?
        /// Wrap lines
        public let wrapsLines: Bool?
        
        public init(
            usesTabs: Bool? = nil,
            indentWidth: UInt? = nil,
            tabWidth: UInt? = nil,
            wrapsLines: Bool? = nil
        ) {
            self.usesTabs = usesTabs
            self.indentWidth = indentWidth
            self.tabWidth = tabWidth
            self.wrapsLines = wrapsLines
        }
    }
}

// MARK: - Options + Codable

extension Project.Options {
    enum CodingKeys: String, CodingKey {
        case textSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.textSettings), try container.decodeNil(forKey: .textSettings) == false {
            var associatedValues = try container.nestedUnkeyedContainer(forKey: .textSettings)
            let textSettings = try associatedValues.decode(TextSettings.self)
            self = .textSettings(textSettings)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .textSettings(textSettings):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .textSettings)
            try associatedValues.encode(textSettings)
        }
    }
}
