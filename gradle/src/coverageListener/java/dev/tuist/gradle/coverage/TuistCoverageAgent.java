package dev.tuist.gradle.coverage;

import java.lang.instrument.Instrumentation;

/**
 * Loaded with {@code -javaagent} only so that its jar joins the test JVM's application class
 * path, where the JUnit Platform finds {@link TuistCoverageListener} as a service. It transforms
 * nothing: the coverage itself is the JaCoCo agent's.
 */
public final class TuistCoverageAgent {
    private TuistCoverageAgent() {
    }

    public static void premain(String arguments, Instrumentation instrumentation) {
    }
}
