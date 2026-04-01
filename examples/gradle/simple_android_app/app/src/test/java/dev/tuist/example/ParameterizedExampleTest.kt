package dev.tuist.example

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource

class ParameterizedExampleTest {
    @ParameterizedTest
    @ValueSource(strings = ["hello", "world", "tuist"])
    fun stringIsNotEmpty(value: String) {
        assertTrue(value.isNotEmpty())
    }

    @ParameterizedTest
    @CsvSource("1, 1, 2", "2, 3, 5", "10, 20, 30")
    fun additionIsCorrect(a: Int, b: Int, expected: Int) {
        assertEquals(expected, a + b)
    }

    @ParameterizedTest
    @ValueSource(ints = [1, 2, 3, 4, 5])
    fun numberIsPositive(value: Int) {
        assertTrue(value > 0)
    }
}
