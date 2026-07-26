import Foundation
import Path
import Testing
@testable import XcodeGraph

struct PackageTests {
    private enum LegacyPackage: Codable {
        case remote(url: String, requirement: Requirement)
        case local(path: AbsolutePath)
    }

    @Test func codableLocal() throws {
        let subject = Package.local(path: try AbsolutePath(validating: "/path/to/workspace"))

        let encoded = try JSONEncoder().encode(subject)

        #expect(try JSONDecoder().decode(Package.self, from: encoded) == subject)
    }

    @Test func codableRemote() throws {
        let subject = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch")
        )

        let encoded = try JSONEncoder().encode(subject)

        #expect(try JSONDecoder().decode(Package.self, from: encoded) == subject)
    }

    @Test func codableRepresentationRemainsUnchanged() throws {
        let package = Package.remote(
            url: "https://example.com/package.git",
            requirement: .exact("1.0.0")
        )
        let legacyPackage = LegacyPackage.remote(
            url: "https://example.com/package.git",
            requirement: .exact("1.0.0")
        )

        let encodedPackage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(package)) as? NSDictionary
        let encodedLegacyPackage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyPackage)) as? NSDictionary

        #expect(encodedPackage == encodedLegacyPackage)
    }

    @Test func identityIsNormalized() throws {
        let local = Package.local(path: try AbsolutePath(validating: "/path/to/LocalPackage"))
        let remote = Package.remote(
            url: "https://example.com/RemotePackage.git",
            requirement: .branch("main")
        )

        #expect(local.identity == "localpackage")
        #expect(remote.identity == "remotepackage")
    }

    @Test func isRemote() throws {
        let local = Package.local(path: try AbsolutePath(validating: "/path/to/package"))
        let remote = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch")
        )

        #expect(local.isRemote == false)
        #expect(remote.isRemote)
    }

    @Test func projectPackageTraitsRoundTripAndRemainOptional() throws {
        let project = Project.test(
            packages: [.local(path: try AbsolutePath(validating: "/path/to/package"))],
            packageTraits: ["package": []]
        )
        let encoded = try JSONEncoder().encode(project)

        #expect(try JSONDecoder().decode(Project.self, from: encoded) == project)

        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "packageTraits")
        let legacyProject = try JSONDecoder().decode(
            Project.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )

        #expect(legacyProject.packageTraits == nil)
    }
}
