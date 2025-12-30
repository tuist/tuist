import Testing

struct Bar {
    let name: String
    @TaskLocal static var current: Bar = .init(name: "global")
}

struct Foo {
    let bar: Bar

    init(bar: Bar = Bar.current) {
        self.bar = bar
    }
}

struct Test {
    @Test func xx() {
        Bar.$current.withValue(Bar(name: "test")) {
            #expect(Foo().bar.name == "test")
        }
    }
}
