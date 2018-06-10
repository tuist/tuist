import XCTest
@testable import xcbuddykit

class UserInputRequesterTests: XCTestCase {
    
    var subject: UserInputRequester!
    var printer: MockPrinter!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        subject = UserInputRequester(printer: printer)
    }
    
    func testOptionalUserInput_ShouldBeNotNil() {
        subject.readBlock = ReadBlockUtils().stringReadBlock
        let input = subject.optional(message: "Optional question")
        XCTAssertEqual(printer.printArgs, ["Optional question"])
        XCTAssertTrue(printer.printArgs.count == 1)
        XCTAssertEqual(input, "xcbuddy")
    }
    
    func testOptionalUserInput_ShouldBeNil() {
        subject.readBlock = ReadBlockUtils().nilReadBlock
        let input = subject.optional(message: "Optional question")
        XCTAssertTrue(printer.printArgs.count == 1)
        XCTAssertNil(input)
    }
    
    func testRequiredUserInput() {
        subject.readBlock = ReadBlockUtils().stringReadBlock
        let input = subject.required(message: "Required question", errorMessage: "error")
        XCTAssertEqual(printer.printArgs, ["Required question"])
        XCTAssertTrue(printer.printArgs.count == 1)
        XCTAssertEqual(input, "xcbuddy")
    }
    
    func testBoolUserInput_ShouldBeYes() {
        subject.readBlock = ReadBlockUtils().booleanYesReadBlock
        let input = subject.bool(message: "Bool question")
        XCTAssertEqual(printer.printArgs, ["Bool question (Y/N)"])
        XCTAssertTrue(printer.printArgs.count == 1)
        XCTAssertEqual(input, true)
    }
    
    func testBoolUserInput_ShouldBeNo() {
        subject.readBlock = ReadBlockUtils().booleanNoReadBlock
        let input = subject.bool(message: "Bool question")
        XCTAssertTrue(printer.printArgs.count == 1)
        XCTAssertEqual(input, false)
    }
}

struct ReadBlockUtils {
    let booleanYesReadBlock = { return "y" }
    let booleanNoReadBlock = { return "n" }
    let stringReadBlock = { return "xcbuddy" }
    let nilReadBlock: () -> String? = { return nil }
}
