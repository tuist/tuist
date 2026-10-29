import AtlasCoreFFI
import Foundation
import Testing

struct AtlasCoreTests {
    @Test func loadsSharedCatalog() {
        let sections = AtlasCore.sections()
        #expect(Array(sections.prefix(5).map(\.title)) == ["Accounts", "Tasks", "Notes", "AI accounts", "Time off"])
        #expect(sections.first { $0.id == "time-off" }?.screen == "time-off")
        #expect(sections.first?.screen == "accounts")
        #expect(sections.allSatisfy { !$0.description.isEmpty })
        #expect(sections.count == Int(atlas_section_count()))
        #expect(AtlasCore.groups().count == Int(atlas_group_count()))
        #expect(sections.first { $0.id == "insurance" }?.requiredScope == "insurance:read")
    }

    @Test func showsOnlyNativeDestinationsAndTheirNonemptyAncestors() {
        let catalog = AtlasCatalog()
        #expect(catalog.children().map(\.id) == ["automation", "overview", "commercial", "people"])
        #expect(catalog.children(of: "commercial").map(\.id) == ["sales", "finance"])
        #expect(catalog.children(of: "operations").isEmpty)
        #expect(catalog.shortcuts.map(\.id) == ["tasks", "time-off"])
        #expect(catalog.entries(in: "people").map(\.id) == ["time-off", "people-directory"])
        #expect(catalog.workspaceSections.map(\.id) == ["accounts", "tasks", "time-off", "finance", "people-directory", "automation"])
        #expect(!catalog.workspaceSections.contains { $0.screen == "browser" })
    }

    @Test func searchesFeaturesAndTheirDomainBreadcrumbs() throws {
        let catalog = AtlasCatalog()
        #expect(catalog.search("  FINANCE ").map(\.id) == ["finance"])
        #expect(catalog.search("engineering").isEmpty)
        #expect(catalog.search("insurance").isEmpty)
        #expect(catalog.search("time off").map(\.id) == ["time-off"])
        #expect(catalog.search("ChatGPT").isEmpty)
        #expect(catalog.search("does-not-exist").isEmpty)
        #expect(catalog.search("  ").isEmpty)
        let account = try #require(catalog.sections.first { $0.id == "accounts" })
        #expect(catalog.breadcrumb(for: account) == "Commercial › Sales")
    }

    @Test func browserDestinationsUseTheSelectedServer() throws {
        let section = try #require(AtlasCatalog().sections.first { $0.id == "accounts" })
        let server = try #require(URL(string: "https://atlas.example.org:4443"))
        #expect(section.destination(on: server).absoluteString == "https://atlas.example.org:4443/commercial/sales/accounts")
    }

    @Test func rejectsInvalidBridgeInputs() {
        #expect(AtlasCore.field(section: -1, id: 0) == nil)
        #expect(AtlasCore.field(section: atlas_section_count(), id: 0) == nil)
        #expect(AtlasCore.field(section: 0, id: 8) == nil)
        #expect(AtlasCore.groupField(group: -1, id: 0) == nil)
        #expect(AtlasCore.groupField(group: atlas_group_count(), id: 0) == nil)
        #expect(AtlasCore.groupField(group: 0, id: 5) == nil)
    }
}
