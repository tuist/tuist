import Testing
@testable import TuistSupport

struct StackTests {
    @Test
    func testEmpty() {
        var stack = Stack<Int>()
        #expect(stack.isEmpty)
        #expect(stack.count == 0)
        #expect(stack.pop() == nil)
    }

    @Test
    func testOneElement() {
        var stack = Stack<Int>()

        stack.push(123)
        #expect(!stack.isEmpty)
        #expect(stack.count == 1)

        let result = stack.pop()
        #expect(result == 123)
        #expect(stack.isEmpty)
        #expect(stack.count == 0)
        #expect(stack.pop() == nil)
    }

    @Test
    func testTwoElements() {
        var stack = Stack<Int>()

        stack.push(123)
        stack.push(456)
        #expect(!stack.isEmpty)
        #expect(stack.count == 2)

        let result1 = stack.pop()
        #expect(result1 == 456)
        #expect(!stack.isEmpty)
        #expect(stack.count == 1)

        let result2 = stack.pop()
        #expect(result2 == 123)
        #expect(stack.isEmpty)
        #expect(stack.count == 0)
        #expect(stack.pop() == nil)
    }

    @Test
    func testMakeEmpty() {
        var stack = Stack<Int>()

        stack.push(123)
        stack.push(456)
        #expect(stack.pop() != nil)
        #expect(stack.pop() != nil)
        #expect(stack.pop() == nil)

        stack.push(789)
        #expect(stack.count == 1)

        let result = stack.pop()
        #expect(result == 789)
        #expect(stack.isEmpty)
        #expect(stack.count == 0)
        #expect(stack.pop() == nil)
    }
}
