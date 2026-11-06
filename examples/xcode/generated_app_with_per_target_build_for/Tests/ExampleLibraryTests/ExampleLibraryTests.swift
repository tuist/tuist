import ExampleLibrary
import Testing

struct ExampleLibraryTests {
    @Test func greeting() {
        #expect(Greeting.message == "Hello from ExampleLibrary")
    }
}
