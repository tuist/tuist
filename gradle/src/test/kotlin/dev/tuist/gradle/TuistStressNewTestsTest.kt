package dev.tuist.gradle

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.gradle.api.logging.Logging
import org.gradle.api.tasks.testing.TestResult
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StressNewTestsModeTest {
    @Test
    fun `environment overrides the declared mode`() {
        assertEquals("enforce", StressNewTestsMode.resolve(environmentValue = "enforce", extensionValue = "report"))
        assertEquals("report", StressNewTestsMode.resolve(environmentValue = "", extensionValue = "report"))
        assertNull(StressNewTestsMode.resolve(environmentValue = null, extensionValue = null))
    }

    @Test
    fun `unknown values switch the gate off`() {
        assertNull(StressNewTestsMode.resolve(environmentValue = "yes", extensionValue = null))
    }
}

class StressRepetitionContextTest {
    @Test
    fun `reads the filters and output file from project properties`() {
        val context = StressRepetitionContext.from(
            mapOf(
                TuistGradleConfig.STRESS_FILTERS_PROPERTY to """{":app:test":["com.example.FooTest.bar"]}""",
                TuistGradleConfig.STRESS_OUTPUT_PROPERTY to "/tmp/out.json"
            )
        )!!
        assertEquals(mapOf(":app:test" to listOf("com.example.FooTest.bar")), context.filtersByTaskPath)
        assertEquals("/tmp/out.json", context.outputFile.path)
        assertNull(StressRepetitionContext.from(emptyMap()))
    }
}

class StressNewTestsGateTest {
    private val logger = Logging.getLogger(StressNewTestsGateTest::class.java)

    private fun executed(name: String, result: TestResult.ResultType = TestResult.ResultType.SUCCESS, quarantined: Boolean = false) =
        ExecutedTestCase(":app", "com.example.CheckoutTest", name, 10, result, quarantined)

    private fun candidate(name: String, repetitions: Int = 10, excluded: String? = null) =
        StressVerdictCandidate(name, "com.example.CheckoutTest", ":app", repetitions, excluded)

    private fun response(vararg candidates: StressVerdictCandidate, guard: StressGuard? = null, enabled: Boolean = true) =
        StressVerdictResponse(enabled, guard, 40, candidates.toList(), StressParameters(200, 600_000))

    private val taskPaths = mapOf(":app" to listOf(":app:test"))

    @Test
    fun `returns null when the account is not entitled`() {
        val gate = StressNewTestsGate("report", { response(enabled = false) }, { _, _, _ -> emptyList() }, logger)
        assertNull(gate.run(listOf(executed("testNew")), taskPaths))
    }

    @Test
    fun `skips when the first pass failed`() {
        var verdictCalls = 0
        val gate = StressNewTestsGate("report", { verdictCalls++; response() }, { _, _, _ -> emptyList() }, logger)
        val report = gate.run(listOf(executed("testNew", TestResult.ResultType.FAILURE)), taskPaths)!!
        assertEquals("skipped", report.outcome)
        assertEquals("first_pass_failed", report.skipReason)
        assertEquals(0, verdictCalls)
    }

    @Test
    fun `a muted failure does not count as a failed first pass`() {
        val gate = StressNewTestsGate("report", { response() }, { _, _, _ -> emptyList() }, logger)
        val report = gate.run(listOf(executed("testMuted", TestResult.ResultType.FAILURE, quarantined = true)), taskPaths)!!
        assertEquals("no_candidates", report.outcome)
    }

    @Test
    fun `records the guard that fired`() {
        val gate = StressNewTestsGate(
            "enforce",
            { response(guard = StressGuard("bulk_change", 70, 100)) },
            { _, _, _ -> emptyList() },
            logger
        )
        val report = gate.run(listOf(executed("testNew")), taskPaths)!!
        assertEquals("skipped", report.outcome)
        assertEquals("bulk_change", report.skipReason)
        assertEquals(70, report.newCount)
        assertEquals(100, report.inventoryCount)
    }

    @Test
    fun `reruns each candidate group once per repetition and prices the outcome`() {
        val runs = mutableListOf<Triple<Map<String, List<String>>, Int, Int>>()
        val gate = StressNewTestsGate(
            "report",
            { response(candidate("testFlaky()"), candidate("testStable()"), candidate("testSlow()", 3), candidate("testTooSlow()", 0, "too_slow")) },
            { filters, repetitions, repetition ->
                runs.add(Triple(filters, repetitions, repetition))
                filters.values.flatten().map { pattern ->
                    val name = pattern.substringAfterLast('.') + "()"
                    val status = if (name == "testFlaky()" && repetition % 2 == 0) "failure" else "success"
                    StressRepetitionResult(":app", "com.example.CheckoutTest", name, status)
                }
            },
            logger
        )

        val report = gate.run(listOf(executed("testFlaky()"), executed("testStable()"), executed("testSlow()"), executed("testTooSlow()")), taskPaths)!!

        assertEquals(13, runs.size)
        assertEquals(10, runs.count { it.second == 10 })
        assertEquals(3, runs.count { it.second == 3 })
        assertEquals(
            mapOf(":app:test" to listOf("com.example.CheckoutTest.testFlaky", "com.example.CheckoutTest.testStable")),
            runs.first { it.second == 10 }.first
        )

        assertEquals("disagreed", report.outcome)
        assertEquals(4, report.newCount)
        assertEquals(3, report.stressedCount)
        assertEquals(1, report.excludedCount)
        val byName = report.testCases.associateBy { it.name }
        assertEquals("disagreed", byName.getValue("testFlaky()").outcome)
        assertEquals(5, byName.getValue("testFlaky()").failedRepetitions)
        assertEquals("passed", byName.getValue("testStable()").outcome)
        assertEquals("passed", byName.getValue("testSlow()").outcome)
        assertEquals(3, byName.getValue("testSlow()").repetitions)
        assertEquals("excluded_too_slow", byName.getValue("testTooSlow()").outcome)
        assertEquals(false, report.blocks)
    }

    @Test
    fun `enforce blocks on a disagreement unless the candidate is muted`() {
        fun gate(mode: String, muted: Boolean) = StressNewTestsGate(
            mode,
            { response(candidate("testFlaky()", 2)) },
            { _, _, repetition ->
                listOf(StressRepetitionResult(":app", "com.example.CheckoutTest", "testFlaky()", if (repetition == 1) "success" else "failure"))
            },
            logger
        ).run(listOf(executed("testFlaky()", quarantined = muted)), taskPaths)!!

        assertTrue(gate("enforce", muted = false).blocks)
        assertEquals(false, gate("report", muted = false).blocks)
        val mutedReport = gate("enforce", muted = true)
        assertEquals(false, mutedReport.blocks)
        assertEquals("passed", mutedReport.outcome)
        assertTrue(mutedReport.testCases.single().isQuarantined)
        assertEquals("disagreed", mutedReport.testCases.single().outcome)
    }

    @Test
    fun `the wall clock ceiling leaves the remaining candidates reported as not stressed`() {
        var now = 0L
        val gate = StressNewTestsGate(
            "report",
            { StressVerdictResponse(true, null, 40, listOf(candidate("testA()", 10), candidate("testB()", 3)), StressParameters(200, 1_000)) },
            { filters, _, _ ->
                now += 2_000_000_000L
                filters.values.flatten().map { StressRepetitionResult(":app", "com.example.CheckoutTest", it.substringAfterLast('.') + "()", "success") }
            },
            logger,
            nanoTime = { now }
        )
        val report = gate.run(listOf(executed("testA()"), executed("testB()")), taskPaths)!!
        val byName = report.testCases.associateBy { it.name }
        assertEquals("not_stressed_ceiling", byName.getValue("testA()").outcome)
        assertEquals("not_stressed_ceiling", byName.getValue("testB()").outcome)
        assertEquals(0, report.stressedCount)
        assertEquals(2, report.excludedCount)
    }

    @Test
    fun `an unreachable server skips the gate without failing the build`() {
        val gate = StressNewTestsGate("enforce", { throw RuntimeException("connection refused") }, { _, _, _ -> emptyList() }, logger)
        val report = gate.run(listOf(executed("testNew")), taskPaths)!!
        assertEquals("skipped", report.outcome)
        assertEquals("verdict_unavailable", report.skipReason)
        assertEquals(false, report.blocks)
    }

    @Test
    fun `filter patterns drop the JUnit 5 parameter list`() {
        assertEquals("com.example.FooTest.bar", StressNewTestsGate.filterPattern("com.example.FooTest", "bar()"))
        assertEquals("com.example.FooTest.bar", StressNewTestsGate.filterPattern("com.example.FooTest", "bar(String)[1]"))
        assertEquals("*.bar", StressNewTestsGate.filterPattern("", "bar"))
    }
}

class TuistStressNewTestsVerdictServiceTest {
    private lateinit var server: MockWebServer

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    private fun service(): TuistStressNewTestsVerdictService {
        val provider = object : ConfigurationProvider {
            override fun getConfiguration(forceRefresh: Boolean) = CacheConfiguration(
                url = server.url("/").toString(),
                token = "test-token",
                accountHandle = "tuist",
                projectHandle = "app"
            )
        }
        return TuistStressNewTestsVerdictService(TuistHttpClient(provider), server.url("/").toString())
    }

    @Test
    fun `posts the executed test cases and parses the verdict`() {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"enabled":true,"guard":null,"inventory_count":40,
                 "candidates":[{"name":"testNew()","suite_name":"com.example.FooTest","module_name":":app","repetitions":10,"excluded_reason":null}],
                 "parameters":{"candidate_cap":200,"wall_clock_ceiling_ms":600000,"bulk_change_ratio":0.3,"bulk_change_floor":50,"repetition_curve":[]}}
                """.trimIndent()
            )
        )

        val verdict = service().verdict(listOf(StressVerdictTestCase("testNew()", "com.example.FooTest", ":app", 12)))

        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/projects/tuist/app/tests/stress-new-tests/verdict", request.path)
        assertEquals("Bearer test-token", request.getHeader("Authorization"))
        assertTrue(request.body.readUtf8().contains("\"module_name\":\":app\""))
        assertTrue(verdict.enabled)
        assertEquals(10, verdict.candidates.single().repetitions)
        assertEquals(600_000, verdict.parameters.wallClockCeilingMs)
    }

    @Test
    fun `a non-200 response is an error the gate reports as unavailable`() {
        server.enqueue(MockResponse().setResponseCode(500).setBody("boom"))
        val error = runCatching { service().verdict(emptyList()) }.exceptionOrNull()
        assertTrue(error != null && error.message!!.contains("HTTP 500"))
    }
}
