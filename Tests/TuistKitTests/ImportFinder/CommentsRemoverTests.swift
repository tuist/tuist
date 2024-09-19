import TuistSupportTesting
import XCTest

@testable import TuistKit

final class CommentsRemoverTests: TuistUnitTestCase {
    var subject: CommentsRemover.Type!

    override func setUp() {
        subject = CommentsRemover.self
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_whenNoComments() throws {
        let code = """
        import a
        """

        let imports = try subject.removeComments(from: code)
        XCTAssertEqual(imports, """
        import a
        """)
    }

    func test_whenOneLineComment() throws {
        let code = """
        //import a
        """

        let imports = try subject.removeComments(from: code)
        XCTAssertEqual(imports, "")
    }

    func test_whenOnePartialComment() throws {
        let code = """
        /*import*/ a
        """

        let imports = try subject.removeComments(from: code)
        XCTAssertEqual(imports, " a")
    }

    func test_whenOneLineAndPartialComment() throws {
        let code = """
        // /**import*/ a
        """

        let imports = try subject.removeComments(from: code)
        XCTAssertEqual(imports, "")
    }

    func test_whenMultilineComment() throws {
        let code = """
            import/*a
            import b
            */
            import c
        """

        let imports = try subject.removeComments(from: code)
        XCTAssertEqual(imports, """
            import
            import c
        """)
    }
}
