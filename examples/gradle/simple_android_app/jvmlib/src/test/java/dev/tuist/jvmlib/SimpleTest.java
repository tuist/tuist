package dev.tuist.jvmlib;

import org.junit.Test;
import static org.junit.Assert.*;

public class SimpleTest {
    @Test
    public void addition_isCorrect() {
        assertEquals(4, 2 + 2);
    }

    @Test
    public void string_isNotEmpty() {
        assertFalse("Hello".isEmpty());
    }
}
