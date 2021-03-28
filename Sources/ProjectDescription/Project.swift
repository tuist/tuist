import Foundation

// MARK: - Project

public struct ResourceSynthesizer: Codable, Equatable {
    public let pluginName: String?
    public let resourceType: ResourceType
    
    public enum ResourceType: String, Codable {
        case strings
    }
    
    public static func strings() -> Self {
        .init(
            pluginName: nil,
            resourceType: .strings
        )
    }
}

public struct Project: Codable, Equatable {
    public let name: String
    public let organizationName: String?
    public let packages: [Package]
    public let targets: [Target]
    public let schemes: [Scheme]
    public let settings: Settings?
    public let fileHeaderTemplate: FileHeaderTemplate?
    public let additionalFiles: [FileElement]
    public let resourceSynthesizers: [ResourceSynthesizer]

    public init(
        name: String,
        organizationName: String? = nil,
        packages: [Package] = [],
        settings: Settings? = nil,
        targets: [Target] = [],
        schemes: [Scheme] = [],
        fileHeaderTemplate: FileHeaderTemplate? = nil,
        additionalFiles: [FileElement] = [],
        resourceSynthesizers: [ResourceSynthesizer] = []
    ) {
        self.name = name
        self.organizationName = organizationName
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
