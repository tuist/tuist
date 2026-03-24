import Foundation
import Path
import Testing
import XcodeGraph

struct BinaryArchitectureTests {
    @Test func test_rawValue() {
        #expect(BinaryArchitecture.x8664.rawValue == "x86_64")
        #expect(BinaryArchitecture.i386.rawValue == "i386")
        #expect(BinaryArchitecture.armv7.rawValue == "armv7")
        #expect(BinaryArchitecture.armv7s.rawValue == "armv7s")
        #expect(BinaryArchitecture.arm64.rawValue == "arm64")
        #expect(BinaryArchitecture.armv7k.rawValue == "armv7k")
        #expect(BinaryArchitecture.arm6432.rawValue == "arm64_32")
    }
}
