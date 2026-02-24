package dev.tuist.example

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ExampleUnitTest {
    @Test
    fun addition_isCorrect() {
        assertEquals(4, 2 + 2)
    }

    @Test
    fun string_isNotEmpty() {
        assertTrue("Hello from Tuist!".isNotEmpty())
    }
}

class AnotherUnitTest {
    @Test
    fun multiplication_isCorrect() {
        assertEquals(6, 2 * 3)
    }

    @Test
    fun subtraction_isCorrect() {
        assertEquals(1, 3 - 2)
    }
}
