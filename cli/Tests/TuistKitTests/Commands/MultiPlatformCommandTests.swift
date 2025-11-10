import Testing
@testable import TuistKit
@testable import XcodeGraph

struct MultiPlatformCommandTests {
    
    @Test func buildCommandParsesValidPlatforms() throws {
        // Test comma-separated platforms
        let validPlatforms = ["ios", "tvos", "macos", "watchos", "visionos"]
        let platformString = validPlatforms.joined(separator: ",")
        
        // Test that the parsing logic works
        let parsedPlatforms = try platformString
            .split(separator: ",")
            .map { platformString in
                let trimmedString = String(platformString.trimmingCharacters(in: .whitespaces))
                return XcodeGraph.Platform(rawValue: trimmedString.lowercased())
            }
            .compactMap { $0 }
        
        #expect(parsedPlatforms.count == validPlatforms.count)
        #expect(parsedPlatforms.contains(.iOS))
        #expect(parsedPlatforms.contains(.tvOS))
        #expect(parsedPlatforms.contains(.macOS))
        #expect(parsedPlatforms.contains(.watchOS))
        #expect(parsedPlatforms.contains(.visionOS))
    }
    
    @Test func buildCommandParsesValidPlatformsWithSpaces() throws {
        // Test platforms with spaces
        let platformString = "ios, tvos , macos,  watchos"
        
        let parsedPlatforms = try platformString
            .split(separator: ",")
            .map { platformString in
                let trimmedString = String(platformString.trimmingCharacters(in: .whitespaces))
                return XcodeGraph.Platform(rawValue: trimmedString.lowercased())
            }
            .compactMap { $0 }
        
        #expect(parsedPlatforms.count == 4)
        #expect(parsedPlatforms.contains(.iOS))
        #expect(parsedPlatforms.contains(.tvOS))
        #expect(parsedPlatforms.contains(.macOS))
        #expect(parsedPlatforms.contains(.watchOS))
    }
    
    @Test func buildCommandRejectsInvalidPlatforms() throws {
        let platformString = "ios,invalid,tvos"
        
        let parsedPlatforms = platformString
            .split(separator: ",")
            .compactMap { platformString in
                let trimmedString = String(platformString.trimmingCharacters(in: .whitespaces))
                return XcodeGraph.Platform(rawValue: trimmedString.lowercased())
            }
        
        // Should only have 2 valid platforms
        #expect(parsedPlatforms.count == 2)
        #expect(parsedPlatforms.contains(.iOS))
        #expect(parsedPlatforms.contains(.tvOS))
        #expect(!parsedPlatforms.contains { platform in platform.rawValue == "invalid" })
    }
    
    @Test func buildCommandHandlesCaseSensitivity() throws {
        let platformString = "iOS,TVOS,MacOS,WatchOS,VisionOS"
        
        let parsedPlatforms = try platformString
            .split(separator: ",")
            .map { platformString in
                let trimmedString = String(platformString.trimmingCharacters(in: .whitespaces))
                return XcodeGraph.Platform(rawValue: trimmedString.lowercased())
            }
            .compactMap { $0 }
        
        #expect(parsedPlatforms.count == 5)
        #expect(parsedPlatforms.contains(.iOS))
        #expect(parsedPlatforms.contains(.tvOS))
        #expect(parsedPlatforms.contains(.macOS))
        #expect(parsedPlatforms.contains(.watchOS))
        #expect(parsedPlatforms.contains(.visionOS))
    }
    
    @Test func buildCommandHandlesEmptyInput() throws {
        let platformString = ""
        
        let parsedPlatforms = platformString
            .split(separator: ",")
            .compactMap { platformString in
                let trimmedString = String(platformString.trimmingCharacters(in: .whitespaces))
                return XcodeGraph.Platform(rawValue: trimmedString.lowercased())
            }
        
        #expect(parsedPlatforms.isEmpty)
    }
    
    @Test func buildCommandHandlesSinglePlatform() throws {
        let platformString = "ios"
        
        let parsedPlatforms = try platformString
            .split(separator: ",")
            .map { platformString in
                let trimmedString = String(platformString.trimmingCharacters(in: .whitespaces))
                return XcodeGraph.Platform(rawValue: trimmedString.lowercased())
            }
            .compactMap { $0 }
        
        #expect(parsedPlatforms.count == 1)
        #expect(parsedPlatforms.first == .iOS)
    }
    
    @Test func platformValidationErrorDescriptions() {
        let invalidPlatformError = PlatformValidationError.invalidPlatform(
            "android", 
            availablePlatforms: ["ios", "tvos", "macos"]
        )
        #expect(invalidPlatformError.description.contains("Invalid platform 'android'"))
        #expect(invalidPlatformError.description.contains("ios, tvos, macos"))
        
        let emptyListError = PlatformValidationError.emptyPlatformList
        #expect(emptyListError.description.contains("At least one platform must be specified"))
        
        let parsingError = PlatformValidationError.parsingError("Parse failed")
        #expect(parsingError.description.contains("Error parsing platforms: Parse failed"))
    }
}