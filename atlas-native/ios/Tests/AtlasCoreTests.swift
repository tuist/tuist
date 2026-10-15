import AtlasCoreFFI
import Testing

struct AtlasCoreTests {
    @Test func loadsSharedCatalog() {
        let sections = AtlasCore.sections()
        #expect(sections.map(\.title) == ["Accounts", "Tasks", "Notes", "AI providers"])
        #expect(sections.map(\.url.path) == ["/commercial/sales/accounts", "/tasks", "/library/notes", "/settings/llm-providers"])
        #expect(sections.allSatisfy { !$0.description.isEmpty })
        #expect(sections.count == Int(atlas_section_count()))
    }

    @Test func rejectsInvalidBridgeInputs() {
        #expect(AtlasCore.field(section: -1, id: 0) == nil)
        #expect(AtlasCore.field(section: atlas_section_count(), id: 0) == nil)
        #expect(AtlasCore.field(section: 0, id: 3) == nil)
    }
}
