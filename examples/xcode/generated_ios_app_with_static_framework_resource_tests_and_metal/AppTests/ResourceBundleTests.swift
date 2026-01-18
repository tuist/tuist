import StaticResourcesFramework
import Testing

struct ResourceBundleTests {
    @Test func readsResourceFromStaticFrameworkBundle() throws {
        let message = try ResourceReader().message()
        #expect(message == "Hello from StaticResourcesFramework")
    }
}
