import Foundation
import Testing

@testable import TuistCore

@Suite
struct AbsoluteUnitOutputParserTests {
    @Test func parses_output_file_and_record_dependencies() {
        // Given real `absolute-unit` output with a mix of system Unit dependencies and a Record.
        let output = """
        ---
        # /tmp/store/v5/units/Greeter-1.o-3MEONWFHWOMDV
        WorkingDirectory: /tmp/checkout
        MainFilePath: /tmp/checkout/Sources/Greeter.swift
        OutputFile: /var/folders/tmp/Greeter-1.o
        ModuleName: CachedLib
        Dependencies:
            - DependencyKind: Unit
              IsSystem: 1
              UnitOrRecordName:\u{0020}
              FilePath: /Applications/Xcode.app/…/Swift.swiftmodule/arm64.swiftinterface
              ModuleName: Swift
            - DependencyKind: Record
              IsSystem: 0
              UnitOrRecordName: Greeter.swift-3HUMJXAQF23WH
              FilePath: /tmp/checkout/Sources/Greeter.swift
              ModuleName:\u{0020}
        """

        // When
        let unit = AbsoluteUnitOutputParser.parse(output)

        // Then
        #expect(unit.outputFile == "/var/folders/tmp/Greeter-1.o")
        // Only the Record dependency's name is collected; the empty system Unit name is ignored.
        #expect(unit.recordNames == ["Greeter.swift-3HUMJXAQF23WH"])
    }

    @Test func ignores_units_with_no_record_dependencies() {
        let output = """
        OutputFile: /var/folders/tmp/Empty.o
        Dependencies:
            - DependencyKind: Unit
              UnitOrRecordName: Swift
        """
        let unit = AbsoluteUnitOutputParser.parse(output)
        #expect(unit.outputFile == "/var/folders/tmp/Empty.o")
        #expect(unit.recordNames.isEmpty)
    }
}
