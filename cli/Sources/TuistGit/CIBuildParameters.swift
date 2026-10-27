import FileSystem
import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif
import Path

/// Build parameters a CI provider passes to build steps in files rather than as environment
/// variables, keyed by parameter name so they can be looked up alongside the environment.
///
/// TeamCity passes only a few parameters as environment variables. The rest, the branch and the
/// pull request among them, are in the parameter files the agent writes for every build:
/// `TEAMCITY_BUILD_PROPERTIES_FILE` names the build's system properties, and its
/// `teamcity.configuration.properties.file` entry names the configuration parameters. The agent
/// writes each of them in Java's XML properties format too, at the same path with `.xml` appended,
/// which is the one read here.
enum CIBuildParameters {
    static func read(environment: [String: String], fileSystem: FileSysteming = FileSystem()) async -> [String: String] {
        guard let buildPropertiesPath = environment["TEAMCITY_BUILD_PROPERTIES_FILE"],
              let buildProperties = await properties(at: buildPropertiesPath, fileSystem: fileSystem)
        else { return [:] }

        var parameters = buildProperties
        if let configurationPropertiesPath = buildProperties["teamcity.configuration.properties.file"],
           let configurationProperties = await properties(at: configurationPropertiesPath, fileSystem: fileSystem)
        {
            parameters.merge(configurationProperties) { buildValue, _ in buildValue }
        }
        // TeamCity calls the default branch `<default>` when no branch specification names it.
        if parameters["teamcity.build.branch"] == "<default>" {
            parameters["teamcity.build.branch"] = nil
        }
        return parameters
    }

    private static func properties(at path: String, fileSystem: FileSysteming) async -> [String: String]? {
        guard let path = try? AbsolutePath(validating: path + ".xml"),
              let contents = try? await fileSystem.readFile(at: path)
        else { return nil }
        return parse(contents)
    }

    /// Parses Java's XML properties format: `<entry key="...">value</entry>` elements in a
    /// `<properties>` root, after a DOCTYPE naming Java's DTD, which is not fetched.
    static func parse(_ data: Data) -> [String: String]? {
        let delegate = PropertiesXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.properties
    }
}

private final class PropertiesXMLDelegate: NSObject, XMLParserDelegate {
    var properties: [String: String] = [:]
    private var key: String?
    private var value = ""

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        guard elementName == "entry" else { return }
        key = attributes["key"]
        value = ""
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if key != nil { value += string }
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        guard elementName == "entry", let key else { return }
        properties[key] = value
        self.key = nil
    }
}
