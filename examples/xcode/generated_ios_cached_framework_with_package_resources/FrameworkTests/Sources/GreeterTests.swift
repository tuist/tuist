import Framework
import Testing

struct GreeterTests {
    @Test func greeting_reads_the_package_resource() {
        #expect(Greeter.greeting() == "Hello from ResourcesLib\n")
    }
}
