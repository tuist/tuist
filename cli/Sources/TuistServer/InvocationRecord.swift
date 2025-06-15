import Foundation

struct InvocationRecord: Codable {
    let actions: XCObjectArray<ActionRecord>
}

struct ActionRecord: Codable {
    let schemeCommandName: XCObjectItem<String>
    let actionResult: ActionResult
}

struct ActionResult: Codable {
    let testsRef: Reference?

    struct Reference: Codable {
        let id: XCObjectItem<String>
    }
}

struct XCObjectArray<T: Codable>: Codable {
    // swiftlint:disable:next identifier_name
    let _values: [T]
}

struct XCObjectItem<T: Codable>: Codable {
    // swiftlint:disable:next identifier_name
    let _value: T
}
