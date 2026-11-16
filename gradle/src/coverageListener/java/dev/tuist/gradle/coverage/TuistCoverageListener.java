package dev.tuist.gradle.coverage;

import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.engine.TestSource;
import org.junit.platform.engine.support.descriptor.ClassSource;
import org.junit.platform.engine.support.descriptor.MethodSource;
import org.junit.platform.launcher.TestExecutionListener;
import org.junit.platform.launcher.TestIdentifier;
import org.junit.platform.launcher.TestPlan;

/**
 * Records which code each test of a test JVM executed, for Tuist's coverage-based test selection.
 *
 * <p>The JaCoCo agent counts into one set of probes for the whole process. At each boundary
 * between scopes (a test starting or finishing, a test class starting or finishing) the listener
 * takes the probes the agent collected since the previous boundary and resets them, so each
 * segment holds what ran in one scope: a test, or a test class outside its tests (its suite). Each
 * segment is appended to the agent's own execution data file, the way the agent appends a dump, so
 * the file still holds everything the process executed, and written with its scope to a file of
 * its own in {@code tuist.coverage.evidence.dir} for the Gradle plugin to read once the task ends.
 *
 * <p>Attribution needs one test at a time per process, which is how Gradle runs tests unless JUnit's
 * parallel execution is turned on. A test that overlaps another is recorded as overlapped, with no
 * segment of its own; what ran then belongs to no scope.
 *
 * <p>Without the system property, a JaCoCo agent writing to a file, or a way to append to that
 * file, the listener does nothing, so it never takes probes it could not give back.
 */
public final class TuistCoverageListener implements TestExecutionListener {
    static final String DIRECTORY_PROPERTY = "tuist.coverage.evidence.dir";

    private final Recorder recorder = Recorder.create();
    private volatile TestPlan plan;

    @Override
    public void testPlanExecutionStarted(TestPlan testPlan) {
        plan = testPlan;
    }

    @Override
    public void executionStarted(TestIdentifier identifier) {
        if (recorder == null) return;
        if (identifier.isTest()) {
            recorder.testStarted(identifier.getUniqueId(), suiteOf(identifier), identifier.getLegacyReportingName());
        } else {
            String className = className(identifier.getSource());
            if (className != null && identifier.getSource().get() instanceof ClassSource) {
                recorder.suiteStarted(identifier.getUniqueId(), className);
            }
        }
    }

    @Override
    public void executionFinished(TestIdentifier identifier, TestExecutionResult result) {
        if (recorder == null) return;
        if (identifier.isTest()) {
            recorder.testFinished(identifier.getUniqueId());
        } else if (identifier.getSource().isPresent() && identifier.getSource().get() instanceof ClassSource) {
            recorder.suiteFinished(identifier.getUniqueId());
        }
    }

    @Override
    public void testPlanExecutionFinished(TestPlan testPlan) {
        if (recorder != null) recorder.flush();
    }

    // The test's class, as Gradle names it in the test's descriptor: its method's class, or the
    // class of the nearest class container above it.
    private String suiteOf(TestIdentifier identifier) {
        TestSource source = identifier.getSource().orElse(null);
        if (source instanceof MethodSource) return ((MethodSource) source).getClassName();
        TestPlan current = plan;
        Optional<TestIdentifier> parent = current == null ? Optional.empty() : current.getParent(identifier);
        while (parent.isPresent()) {
            String className = className(parent.get().getSource());
            if (className != null) return className;
            parent = current.getParent(parent.get());
        }
        return "";
    }

    private static String className(Optional<TestSource> source) {
        if (!source.isPresent()) return null;
        if (source.get() instanceof ClassSource) return ((ClassSource) source.get()).getClassName();
        if (source.get() instanceof MethodSource) return ((MethodSource) source.get()).getClassName();
        return null;
    }

    static final class Recorder {
        static final int SEGMENT = 1;
        static final int OVERLAPPED = 2;

        private final Object agent;
        private final Method executionData;
        private final File execFile;
        private final File output;
        private DataOutputStream stream;
        private boolean broken;

        private final Map<String, Running> tests = new HashMap<String, Running>();
        private final Map<String, String> suites = new LinkedHashMap<String, String>();
        private boolean suitesOverlapped;

        private Recorder(Object agent, Method executionData, File execFile, File output) {
            this.agent = agent;
            this.executionData = executionData;
            this.execFile = execFile;
            this.output = output;
        }

        static Recorder create() {
            String directory = System.getProperty(DIRECTORY_PROPERTY);
            if (directory == null || directory.isEmpty()) return null;
            try {
                File execFile = jacocoExecFile(ManagementFactory.getRuntimeMXBean().getInputArguments());
                if (execFile == null) return null;
                Object agent = Class.forName("org.jacoco.agent.rt.RT").getMethod("getAgent").invoke(null);
                Method executionData = Class.forName("org.jacoco.agent.rt.IAgent")
                    .getMethod("getExecutionData", boolean.class);
                // As the agent does at startup: never reset probes that could not be appended back.
                new FileOutputStream(execFile, true).close();
                File output = new File(directory, UUID.randomUUID() + ".evidence");
                return new Recorder(agent, executionData, execFile, output);
            } catch (Throwable error) {
                return null;
            }
        }

        /**
         * The file the JaCoCo agent of this JVM writes to, or null when there is no agent or it
         * writes elsewhere ({@code output=tcpserver}, {@code tcpclient}, {@code none}).
         */
        static File jacocoExecFile(List<String> arguments) {
            for (String argument : arguments) {
                if (!argument.startsWith("-javaagent:")) continue;
                int jar = argument.indexOf(".jar=");
                String path = jar < 0 ? argument : argument.substring(0, jar + 4);
                if (!new File(path.substring("-javaagent:".length())).getName().startsWith("jacocoagent")) continue;
                String destfile = "jacoco.exec";
                String output = "file";
                if (jar >= 0) {
                    for (String option : argument.substring(jar + 5).split(",")) {
                        int equals = option.indexOf('=');
                        if (equals < 0) continue;
                        String key = option.substring(0, equals);
                        String value = option.substring(equals + 1);
                        if (key.equals("destfile")) destfile = value;
                        if (key.equals("output")) output = value;
                    }
                }
                if (!output.equals("file")) return null;
                File file = new File(destfile);
                return file.isAbsolute() ? file : new File(System.getProperty("user.dir"), destfile);
            }
            return null;
        }

        synchronized void testStarted(String id, String suite, String name) {
            if (tests.isEmpty()) boundary(outside());
            boolean overlapped = !tests.isEmpty();
            if (overlapped) {
                for (Running running : tests.values()) running.overlapped = true;
            }
            tests.put(id, new Running(suite, name, overlapped));
        }

        synchronized void testFinished(String id) {
            Running test = tests.remove(id);
            if (test == null) return;
            if (test.overlapped) {
                record(OVERLAPPED, null, test.suite, test.name, null);
                // What ran while tests overlapped belongs to none of them.
                if (tests.isEmpty()) boundary(null);
            } else {
                boundary(new String[] {"test", test.suite, test.name});
            }
        }

        synchronized void suiteStarted(String id, String className) {
            if (tests.isEmpty()) boundary(outside());
            suites.put(id, className);
            if (suites.size() > 1) suitesOverlapped = true;
        }

        synchronized void suiteFinished(String id) {
            if (tests.isEmpty()) boundary(outside());
            suites.remove(id);
            if (suites.isEmpty()) suitesOverlapped = false;
        }

        synchronized void flush() {
            if (stream == null) return;
            try {
                stream.flush();
            } catch (IOException error) {
                broken = true;
            }
        }

        // What runs outside any test belongs to the suite when exactly one test class is running.
        private String[] outside() {
            if (suites.size() != 1 || suitesOverlapped) return null;
            return new String[] {"suite", suites.values().iterator().next(), ""};
        }

        private void boundary(String[] scope) {
            if (broken) return;
            byte[] data;
            try {
                data = (byte[]) executionData.invoke(agent, true);
            } catch (Throwable error) {
                broken = true;
                return;
            }
            if (!append(data)) {
                broken = true;
                return;
            }
            if (scope != null) record(SEGMENT, scope[0], scope[1], scope[2], data);
        }

        // Appended under a lock, as the JaCoCo agent appends its own dumps, so the other test JVMs of
        // the task that write to the same file never interleave with this one.
        private boolean append(byte[] data) {
            FileOutputStream file = null;
            try {
                file = new FileOutputStream(execFile, true);
                file.getChannel().lock();
                file.write(data);
                return true;
            } catch (IOException error) {
                return false;
            } finally {
                if (file != null) {
                    try {
                        file.close();
                    } catch (IOException ignored) {
                    }
                }
            }
        }

        private void record(int type, String kind, String suite, String name, byte[] data) {
            try {
                if (stream == null) {
                    File parent = output.getParentFile();
                    if (parent != null) parent.mkdirs();
                    stream = new DataOutputStream(new BufferedOutputStream(new FileOutputStream(output, true)));
                }
                stream.writeByte(type);
                if (type == SEGMENT) writeString(kind);
                writeString(suite);
                writeString(name);
                if (type == SEGMENT) {
                    stream.writeInt(data.length);
                    stream.write(data);
                }
                stream.flush();
            } catch (IOException error) {
                // The segment is already in the execution data file; only its attribution is lost.
            }
        }

        private void writeString(String value) throws IOException {
            byte[] bytes = (value == null ? "" : value).getBytes(StandardCharsets.UTF_8);
            stream.writeInt(bytes.length);
            stream.write(bytes);
        }

        private static final class Running {
            final String suite;
            final String name;
            boolean overlapped;

            Running(String suite, String name, boolean overlapped) {
                this.suite = suite;
                this.name = name;
                this.overlapped = overlapped;
            }
        }
    }
}
