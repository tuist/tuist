package dev.tuist.gradle

import com.google.gson.JsonParser
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ReportOutboxTest {
    @TempDir lateinit var directory: File

    private lateinit var server: MockWebServer
    private val arrivals = CopyOnWriteArrayList<Arrival>()
    @Volatile private var respond: (String, String) -> MockResponse = { _, _ -> MockResponse().setResponseCode(201).setBody("{}") }

    private data class Arrival(val path: String, val id: String, val body: String, val authorization: String?, val pending: List<String>)

    private val outboxDirectory get() = File(directory, "outbox")

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val body = request.body.readUtf8()
                val id = JsonParser.parseString(body).asJsonObject["id"].asString
                val path = request.path.orEmpty()
                arrivals.add(Arrival(path, id, body, request.getHeader("Authorization"), pendingIds()))
                return respond(path, id)
            }
        }
        server.start()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `persists an authenticated report before sending it and deletes it once accepted`() {
        val id = newId()

        val result = publish(id)

        assertEquals(201, result.status)
        assertEquals(listOf(listOf(id)), arrivals.map { it.pending })
        assertEquals("Bearer token", arrivals.single().authorization)
        assertEquals(emptyList(), pendingIds())
    }

    @Test
    fun `a report the server could not take is sent again with the same id and body after the next accepted report`() {
        val first = newId()
        val second = newId()
        respond = { _, id -> if (id == first) MockResponse().setResponseCode(503) else MockResponse().setResponseCode(201).setBody("{}") }

        val failure = runCatching { publish(first) }.exceptionOrNull()
        assertTrue(failure != null, "the first report must fail")
        assertEquals(listOf(first), pendingIds())
        val originalBody = arrivals.first().body

        respond = { _, _ -> MockResponse().setResponseCode(201).setBody("{}") }
        publish(second, kind = ReportKind.TEST_RUN)

        assertEquals(listOf(first, first, first, first, second, first), arrivals.map { it.id })
        val replay = arrivals.last()
        assertEquals(originalBody, replay.body)
        assertEquals("/api/projects/acme/app/gradle/builds", replay.path)
        assertEquals(emptyList(), pendingIds())
    }

    @Test
    fun `a report whose connections were dropped is kept and sent again`() {
        val first = newId()
        val second = newId()
        respond = { _, id ->
            if (id == first) MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST) else MockResponse().setResponseCode(201).setBody("{}")
        }

        assertTrue(runCatching { publish(first) }.isFailure)
        assertEquals(listOf(first), pendingIds())

        respond = { _, _ -> MockResponse().setResponseCode(201).setBody("{}") }
        publish(second)

        assertEquals(listOf(second, first), arrivals.dropWhile { it.id == first }.map { it.id })
        assertEquals(emptyList(), pendingIds())
    }

    @ParameterizedTest
    @ValueSource(ints = [400, 403, 404, 422])
    fun `a permanent refusal deletes the report`(status: Int) {
        val first = newId()
        respond = { _, id -> if (id == first) MockResponse().setResponseCode(status) else MockResponse().setResponseCode(201).setBody("{}") }

        assertEquals(status, publish(first).status)
        assertEquals(emptyList(), pendingIds())

        publish(newId())
        assertEquals(1, arrivals.count { it.id == first })
    }

    @ParameterizedTest
    @ValueSource(ints = [408, 429, 500])
    fun `a transient refusal keeps the report`(status: Int) {
        val first = newId()
        respond = { _, _ -> MockResponse().setResponseCode(status) }

        assertEquals(status, publish(first).status)

        assertEquals(listOf(first), pendingIds())
    }

    @Test
    fun `expired reports are deleted without being sent`() {
        val first = newId()
        val now = System.currentTimeMillis()
        respond = { _, _ -> MockResponse().setResponseCode(503) }
        runCatching { publish(first, outbox = ReportOutbox(outboxDirectory, clock = { now }), createdAtMs = now) }
        assertEquals(listOf(first), pendingIds())

        respond = { _, _ -> MockResponse().setResponseCode(201).setBody("{}") }
        val later = now + TimeUnit.MINUTES.toMillis(46)
        val second = newId()
        publish(second, outbox = ReportOutbox(outboxDirectory, clock = { later }), createdAtMs = later)

        assertEquals(listOf(second), arrivals.dropWhile { it.id == first }.map { it.id })
        assertEquals(emptyList(), pendingIds())
    }

    @Test
    fun `the oldest reports are dropped beyond the count and size bounds`() {
        val ids = List(5) { newId() }
        val now = System.currentTimeMillis()
        val byCount = ReportOutbox(outboxDirectory, maxEntries = 3)
        ids.forEachIndexed { index, id -> byCount.deliver(entry(id, createdAtMs = now + index)) { ReportPostResult(503, null) } }
        assertEquals(ids.takeLast(3), pendingIds())

        val entrySize = outboxDirectory.listFiles()!!.filter { it.name.endsWith(".json") }.maxOf { it.length() }
        val bySize = ReportOutbox(outboxDirectory, maxBytes = entrySize * 2)
        val newest = newId()
        bySize.deliver(entry(newest, createdAtMs = now + 10)) { ReportPostResult(503, null) }
        assertEquals(listOf(ids.last(), newest), pendingIds())
    }

    @Test
    fun `corrupt reports are deleted without being sent`() {
        outboxDirectory.mkdirs()
        val corrupt = File(outboxDirectory, "${System.currentTimeMillis()}-${newId()}.json").apply { writeText("{not json") }
        val mismatched = File(outboxDirectory, "${System.currentTimeMillis()}-${newId()}.json").apply {
            writeText(com.google.gson.Gson().toJson(entry(newId())))
        }

        publish(newId())

        assertEquals(1, arrivals.size)
        assertTrue(!corrupt.exists() && !mismatched.exists())
    }

    @Test
    fun `credential-free reports are never persisted`() {
        respond = { _, _ -> MockResponse().setResponseCode(503) }

        assertTrue(runCatching { publish(newId(), token = "") }.isFailure)

        assertEquals(4, arrivals.size)
        assertTrue(arrivals.all { it.authorization == null && it.pending.isEmpty() })
        assertEquals(emptyList(), pendingIds())
    }

    @Test
    fun `pending reports are only sent with credentials to the project and server they were made for`() {
        val first = newId()
        respond = { _, _ -> MockResponse().setResponseCode(503) }
        runCatching { publish(first) }
        respond = { _, _ -> MockResponse().setResponseCode(201).setBody("{}") }
        arrivals.clear()

        publish(newId(), token = "")
        publish(newId(), project = "other")

        assertEquals(2, arrivals.size)
        assertTrue(arrivals.none { it.id == first })
        assertEquals(listOf(first), pendingIds())
    }

    @Test
    fun `a replay that fails does not fail the report and keeps the pending report`() {
        val first = newId()
        respond = { _, _ -> MockResponse().setResponseCode(503) }
        runCatching { publish(first) }
        respond = { _, id -> if (id == first) MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST) else MockResponse().setResponseCode(201).setBody("{}") }

        val result = publish(newId())

        assertEquals(201, result.status)
        assertEquals(listOf(first), pendingIds())
    }

    @Test
    fun `a replay sends a bounded number of pending reports, oldest first`() {
        val pending = List(7) { newId() }
        val outbox = ReportOutbox(outboxDirectory)
        val url = ReportKind.BUILD.url(server.url("/").toString(), config("token", "app")).toString()
        pending.forEachIndexed { index, id ->
            outbox.deliver(entry(id, url = url, createdAtMs = System.currentTimeMillis() - 10_000 + index)) { ReportPostResult(503, null) }
        }

        val current = newId()
        publish(current)

        assertEquals(listOf(current) + pending.take(5), arrivals.map { it.id })
        assertEquals(pending.takeLast(2), pendingIds())
    }

    private fun publish(
        id: String,
        token: String = "token",
        project: String = "app",
        kind: ReportKind = ReportKind.BUILD,
        outbox: ReportOutbox = ReportOutbox(outboxDirectory),
        createdAtMs: Long = System.currentTimeMillis()
    ): ReportPostResult {
        val httpClient = TuistHttpClient(
            configurationProvider = object : ConfigurationProvider {
                override fun getConfiguration(forceRefresh: Boolean) = config(token, project)
            },
            httpClients = TuistHttpClients(useEnvironmentProxy = false, retryPolicy = RetryPolicy(sleeper = {}))
        )
        return httpClient.execute { config ->
            publishReport(
                outbox = outbox, httpClient = httpClient, config = config, baseUrl = server.url("/").toString(),
                kind = kind, id = id, createdAtMs = createdAtMs, body = "{\"id\":\"$id\",\"value\":\"${UUID.randomUUID()}\"}",
                actorId = null, description = "Report"
            )
        }
    }

    private fun config(token: String, project: String) =
        CacheConfiguration(url = server.url("/").toString(), token = token, accountHandle = "acme", projectHandle = project)

    private fun entry(id: String, url: String = "http://localhost/", createdAtMs: Long = System.currentTimeMillis()) =
        ReportOutboxEntry(ReportKind.BUILD, id, url, createdAtMs, null, "{\"id\":\"$id\"}")

    private fun pendingIds(): List<String> =
        outboxDirectory.listFiles().orEmpty()
            .filter { it.name.endsWith(".json") }
            .sortedBy { it.name.substringBefore('-').toLong() }
            .map { it.name.substringAfter('-').removeSuffix(".json") }

    private fun newId() = UUID.randomUUID().toString()
}
