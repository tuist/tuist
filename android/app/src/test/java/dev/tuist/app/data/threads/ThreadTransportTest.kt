package dev.tuist.app.data.threads

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.util.UUID
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.logging.HttpLoggingInterceptor
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import com.squareup.moshi.JsonDataException
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.Retrofit
import retrofit2.HttpException

class ThreadTransportTest {
    private val moshi = Moshi.Builder().addLast(KotlinJsonAdapterFactory()).build()
    private val requests = mutableListOf<Request>()
    private var response = """{"threads":[],"next_cursor":"opaque+/="}"""
    private val retrofit =
        Retrofit.Builder()
            .baseUrl("https://selected.example/prefix/")
            .client(
                OkHttpClient.Builder()
                    .addInterceptor { chain ->
                        val authenticated =
                            chain
                                .request()
                                .newBuilder()
                                .header("Authorization", "Bearer test-only")
                                .build()
                        // Existing payload assertions exclude the separate capability probe.
                        val probe = authenticated.url.encodedPath.endsWith("/models") && !response.contains("\"models\"")
                        if (!probe) requests.add(authenticated)
                        Response.Builder()
                            .request(authenticated)
                            .protocol(Protocol.HTTP_1_1)
                            .code(200)
                            .message("OK")
                            .body((if (probe) """{"models":[],"errors":[]}""" else response).toResponseBody("application/json".toMediaType()))
                            .build()
                    }
                    .build()
            )
            .build()
    private val api = ThreadTransport(retrofit, moshi).api
    private val thread =
        """{"id":"t","title":"Title","goal":"Goal","repository":"","branch":"", "profile":"linux",
        "provider":"chatgpt","model":"model-id",
        "status":"completed","visibility":"private","messages":[],"diff":"","revision":3,"has_more":false} """

    @Test
    fun `list preserves selected origin and opaque pagination`() = runTest {
        assertEquals("opaque+/=", api.list("acme", "cursor+/=").nextCursor)
        assertEquals("selected.example", requests.single().url.host)
        assertEquals("/prefix/api/accounts/acme/threads", requests.single().url.encodedPath)
        assertEquals("cursor+/=", requests.single().url.queryParameter("cursor"))
    }

    @Test
    fun `creation sends null repository and stable request id without fake host`() = runTest {
        response = thread
        val body =
            CreateThread(
                "Explain this",
                provider = "chatgpt",
                model = "model-id",
                requestId = "fixed-id",
            )
        val created = api.create("acme", body)
        assertEquals("chatgpt", created.provider)
        assertEquals("model-id", created.model)
        val serialized = Buffer().also { requests.single().body!!.writeTo(it) }.readUtf8()
        assertTrue(serialized.contains("\"repository\":null"))
        assertTrue(serialized.contains("\"provider\":\"chatgpt\""))
        assertTrue(serialized.contains("\"model\":\"model-id\""))
        assertTrue(serialized.contains("\"request_id\":\"fixed-id\""))
        assertTrue(!serialized.contains("profile"))
        assertEquals("POST", requests.single().method)
    }

    @Test
    fun `repository creation preserves exact selection and request identity on replay`() = runTest {
        response = thread
        val body =
            CreateThread("Private prompt", "chatgpt", "model-id", "acme/private", "release/next")
        assertEquals(body.requestId, UUID.fromString(body.requestId).toString())
        api.create("acme", body)
        api.create("acme", body)
        val serialized = requestBody(requests.first())
        assertEquals(serialized, requestBody(requests.last()))
        assertEquals(
            mapOf(
                "content" to "Private prompt",
                "provider" to "chatgpt",
                "model" to "model-id",
                "repository" to "acme/private",
                "base_branch" to "release/next",
                "request_id" to body.requestId,
            ),
            moshi.adapter(Map::class.java).fromJson(serialized),
        )
    }

    @Test
    fun `repositories decode backend snake case names without inventing defaults`() = runTest {
        response =
            """{"repositories":[{"full_name":"acme/private","default_branch":"trunk","ignored":true}]}"""
        assertEquals(
            listOf(ThreadRepository("acme/private", "trunk")),
            api.repositories("acme").repositories,
        )
        assertEquals(
            "/prefix/api/accounts/acme/threads/repositories",
            requests.single().url.encodedPath,
        )
    }

    @Test
    fun `history decodes nullable model tool fields and integer pagination`() = runTest {
        response =
            thread
                .replace(
                    "\"provider\":\"chatgpt\",\"model\":\"model-id\"",
                    "\"provider\":null,\"model\":null",
                )
                .replace(
                    "\"has_more\":false",
                    "\"has_more\":true,\"next_before\":42,\"archive_status\":\"archived\"",
                )
                .replace(
                    "\"messages\":[]",
                    """"messages":[
                {"id":"m1","role":"user","content":"private prompt","position":42,
                 "toolName":null,"toolStatus":null,"suggestions":null,"createdAt":"2026-11-06T09:00:00Z"},
                {"id":"m2","role":"tool","content":"original output","position":43,
                 "toolName":"read_file","toolStatus":"completed","suggestions":[],
                 "createdAt":"2026-11-06T09:01:00Z"}]
            """
                        .trimIndent(),
                )
        val history = api.history("acme", "t", before = 44)
        assertNull(history.provider)
        assertNull(history.model)
        assertEquals("", history.repository)
        assertEquals("", history.branch)
        assertEquals(3, history.revision)
        assertEquals(true, history.hasMore)
        assertEquals(42, history.nextBefore)
        assertEquals("archived", history.archiveStatus)
        assertEquals(listOf(42, 43), history.messages.map { it.position })
        assertNull(history.messages.first().toolName)
        assertNull(history.messages.first().suggestions)
        assertEquals("read_file", history.messages.last().toolName)
        assertEquals("completed", history.messages.last().toolStatus)
        assertEquals("2026-11-06T09:01:00Z", history.messages.last().createdAt)
        assertNull(history.messages.last().richContent)
        assertEquals("44", requests.single().url.queryParameter("before"))
        assertEquals("GET", requests.single().method)
    }

    @Test
    fun `unpaged history and terminal inbox accept null cursors`() = runTest {
        response = thread.replace("\"has_more\":false", "\"has_more\":false,\"next_before\":null")
        assertNull(api.history("acme", "t").nextBefore)
        assertNull(requests.single().url.query)
        response = """{"threads":[$thread],"next_cursor":null}"""
        val inbox = api.list("acme")
        assertNull(inbox.nextCursor)
        assertEquals(emptyList<ThreadMessage>(), inbox.threads.single().messages)
    }

    @Test
    fun `optional rich presentation never changes transcript or invokes an action`() = runTest {
        response =
            thread.replace(
                "\"messages\":[]",
                """"messages":[
            {"id":"m","role":"assistant","content":"Original transcript","suggestions":["Ship"],
             "toolInput":null,"parentMessageID":null,"richContent":"unsupported future presentation"}]
        """
                    .trimIndent(),
            )
        val message = api.history("acme", "t").messages.single()
        assertEquals("Original transcript", message.content)
        assertEquals(listOf("Ship"), message.suggestions)
        assertEquals("unsupported future presentation", message.richContent)
        assertEquals(1, requests.size)
        assertEquals("GET", requests.single().method)
    }

    @Test
    fun `rich content extensions and tool metadata retain camel case wire names`() = runTest {
        response =
            thread.replace(
                "\"messages\":[]",
                """"messages":[
            {"id":"tool","role":"tool","content":"Plain text fallback","toolName":"test",
             "toolStatus":"failed","toolInput":"test --filter Private","parentMessageID":"parent",
             "richContent":{"kind":"test_results","facts":[{"label":"Passed","value":"2"}],
                            "future":true,"nullable":null}}]
        """
                    .trimIndent(),
            )
        val message = api.history("acme", "t").messages.single()
        assertEquals("Plain text fallback", message.content)
        assertEquals("test --filter Private", message.toolInput)
        assertEquals("parent", message.parentMessageID)
        assertEquals("failed", message.toolStatus)
        val rich = message.richContent as Map<*, *>
        assertEquals("test_results", rich["kind"])
        assertEquals(listOf(mapOf("label" to "Passed", "value" to "2")), rich["facts"])
        assertEquals(true, rich["future"])
        assertTrue(rich.containsKey("nullable"))
        assertNull(rich["nullable"])
    }

    @Test
    fun `suggested Ship text is only a message with a stable request id`() = runTest {
        response = thread
        val body = SendMessage("Ship")
        assertEquals(body.requestId, UUID.fromString(body.requestId).toString())
        api.send("acme", "t", body)
        api.send("acme", "t", body)
        assertEquals(requestBody(requests.first()), requestBody(requests.last()))
        assertTrue(requests.all { it.url.pathSegments.last() == "messages" })
        assertEquals(
            mapOf("content" to "Ship", "request_id" to body.requestId),
            moshi.adapter(Map::class.java).fromJson(requestBody(requests.last())),
        )
    }

    @Test
    fun `catalog uses selected authenticated origin and retains partial errors`() = runTest {
        response =
            """{"models":[{"provider":"chatgpt","id":"model-id","name":"Display name"}],
            "errors":[{"provider":"claude","code":"unsupported_subscription"}]}"""
        val catalog = api.models("acme")
        assertEquals(listOf(ThreadModel("chatgpt", "model-id", "Display name")), catalog.models)
        assertEquals(listOf(ThreadModelError("claude", "unsupported_subscription")), catalog.errors)
        assertEquals(
            "https://selected.example/prefix/api/accounts/acme/threads/models",
            requests.single().url.toString(),
        )
        assertEquals("Bearer test-only", requests.single().header("Authorization"))
    }

    @Test
    fun `empty catalog does not invent access`() = runTest {
        response = """{"models":[],"errors":[]}"""
        assertTrue(api.models("acme").models.isEmpty())
        response = """{"models":[],"errors":[{"provider":"claude","code":"models_unavailable"}]}"""
        val unavailable = api.models("acme")
        assertTrue(unavailable.models.isEmpty())
        assertEquals("models_unavailable", unavailable.errors.single().code)
    }

    @Test
    fun `shipping preview and explicit approval are distinct operations`() = runTest {
        response =
            """{"head_sha":"head","base_sha":"base","diff":"patch","target_branch":"main",
            "mode":"direct","request_id":"review-id","repository":"acme/private","thread_id":"t",
            "account_id":12,"sandbox_id":"sandbox","actor":"GitHub App installation (Tuist Threads)"}"""
        val preview = api.shipPreview("acme", "t")
        assertEquals(1, requests.size)
        assertEquals("ship-preview", requests.single().url.pathSegments.last())
        assertEquals("acme/private", preview.repository)
        assertEquals("GitHub App installation (Tuist Threads)", preview.actor)
        assertEquals(12L, preview.accountId)
        assertEquals("t", preview.threadId)
        assertEquals("sandbox", preview.sandboxId)
        response = thread
        val approval = ShipApproval(preview)
        api.ship("acme", "t", approval)
        api.ship("acme", "t", approval)
        assertEquals("ship", requests.last().url.pathSegments.last())
        assertEquals(requestBody(requests[1]), requestBody(requests[2]))
        assertEquals(
            mapOf(
                "request_id" to "review-id",
                "head_sha" to "head",
                "base_sha" to "base",
                "target_branch" to "main",
                "mode" to "direct",
            ),
            moshi.adapter(Map::class.java).fromJson(requestBody(requests.last())),
        )
    }

    @Test
    fun `archive sends only the backend status field`() = runTest {
        response = thread
        api.archive("acme", "t", ArchiveThread("archived"))
        assertEquals("PATCH", requests.single().method)
        assertEquals("""{"status":"archived"}""", requestBody(requests.single()))
    }

    @Test
    fun `private prompts and responses bypass logging without mutating the shared client`() =
        runTest {
            val logs = mutableListOf<String>()
            val applicationLogger =
                HttpLoggingInterceptor { logs.add(it) }.setLevel(HttpLoggingInterceptor.Level.BODY)
            val networkLogger =
                HttpLoggingInterceptor { logs.add(it) }.setLevel(HttpLoggingInterceptor.Level.BODY)
            val original = retrofit.callFactory() as OkHttpClient
            val shared =
                original
                    .newBuilder()
                    .apply {
                        interceptors().add(0, applicationLogger)
                        addNetworkInterceptor(networkLogger)
                    }
                    .build()
            val privateApi =
                ThreadTransport(retrofit.newBuilder().client(shared).build(), moshi).api
            response = thread.replace("Goal", "private response")
            privateApi.create("acme", CreateThread("private prompt", "chatgpt", "model-id"))
            assertTrue(logs.isEmpty())
            assertEquals("Bearer test-only", requests.single().header("Authorization"))
            assertEquals("selected.example", requests.single().url.host)
            assertTrue(shared.interceptors.contains(applicationLogger))
            assertTrue(shared.networkInterceptors.contains(networkLogger))
            assertFalse(original.interceptors.contains(applicationLogger))
        }

    @Test
    fun `public reads support both server dialects and required page aliases`() = runTest {
        MockWebServer().use { server ->
            val api = ThreadTransport(Retrofit.Builder().baseUrl(server.url("/prefix/")).build(), moshi).api
            server.enqueue(MockResponse().setBody("""{"threads":[$thread],"next_cursor":"new"}"""))
            assertEquals("t", api.list("acme").threads.single().id)
            assertEquals("/prefix/api/accounts/acme/threads", server.takeRequest().path)
            server.enqueue(MockResponse().setResponseCode(404))
            server.enqueue(MockResponse().setBody("""{"jams":[$thread],"next_cursor":"old"}"""))
            val page = api.list("acme", "opaque+/=")
            assertEquals("old", page.nextCursor)
            assertEquals("t", page.threads.single().id)
            assertEquals("/prefix/api/accounts/acme/threads", server.takeRequest().requestUrl!!.encodedPath)
            val legacy = server.takeRequest()
            assertEquals("/prefix/api/accounts/acme/jams", legacy.requestUrl!!.encodedPath)
            assertEquals("opaque+/=", legacy.requestUrl!!.queryParameter("cursor"))
            server.enqueue(MockResponse().setBody("""{"threads":[],"jams":[$thread]}"""))
            assertTrue(api.list("acme").threads.isEmpty())
            server.takeRequest()
            for (body in listOf("{}", """{"jams":null}""", """{"threads":null,"jams":[]}""", """{"jams":{}}""")) {
                server.enqueue(MockResponse().setBody(body))
                try {
                    api.list("acme")
                    org.junit.Assert.fail("Malformed page accepted: $body")
                } catch (_: JsonDataException) { }
                server.takeRequest()
            }
            assertEquals(8, server.requestCount)
        }
    }

    @Test
    fun `catalog repository and history reads prefer threads and safely negotiate legacy jams`() = runTest {
        for (dialect in listOf("threads", "jams")) {
            for (operation in listOf("models", "repositories", "history")) {
                MockWebServer().use { server ->
                    val api = ThreadTransport(Retrofit.Builder().baseUrl(server.url("/")).build(), moshi).api
                    if (dialect == "jams") server.enqueue(MockResponse().setResponseCode(404))
                    val body = when (operation) {
                        "models" -> """{"models":[],"errors":[]}"""
                        "repositories" -> """{"repositories":[]}"""
                        else -> thread
                    }
                    server.enqueue(MockResponse().setBody(body))
                    when (operation) {
                        "models" -> assertTrue(api.models("acme").models.isEmpty())
                        "repositories" -> assertTrue(api.repositories("acme").repositories.isEmpty())
                        else -> assertEquals("t", api.history("acme", "t", before = 42).id)
                    }
                    val suffix = if (operation == "history") "t?before=42" else operation
                    val canonical = server.takeRequest()
                    assertEquals("GET", canonical.method)
                    assertEquals("/api/accounts/acme/threads/$suffix", canonical.path)
                    if (dialect == "jams") {
                        val legacy = server.takeRequest()
                        assertEquals("GET", legacy.method)
                        assertEquals("/api/accounts/acme/jams/$suffix", legacy.path)
                    }
                    assertEquals(if (dialect == "jams") 2 else 1, server.requestCount)
                }
            }
        }
    }

    @Test
    fun `every mutation probes safely and sends once even on mutation 404`() = runTest {
        for (dialect in listOf("threads", "jams")) {
            for (operation in listOf("create", "send", "archive", "ship-preview", "ship")) {
                MockWebServer().use { server ->
                    val api = ThreadTransport(Retrofit.Builder().baseUrl(server.url("/")).build(), moshi).api
                    if (dialect == "jams") server.enqueue(MockResponse().setResponseCode(404))
                    server.enqueue(MockResponse().setBody("""{"models":[],"errors":[]}"""))
                    server.enqueue(MockResponse().setResponseCode(404))
                    try {
                        when (operation) {
                            "create" -> api.create("acme", CreateThread("prompt", "chatgpt", "model"))
                            "send" -> api.send("acme", "t", SendMessage("hello"))
                            "archive" -> api.archive("acme", "t", ArchiveThread("archived"))
                            "ship-preview" -> api.shipPreview("acme", "t")
                            "ship" -> api.ship("acme", "t", ShipApproval("request", "head", "base", "main", "direct"))
                        }
                        org.junit.Assert.fail("Expected mutation failure")
                    } catch (error: HttpException) {
                        assertEquals(404, error.code())
                    }
                    val count = if (dialect == "jams") 3 else 2
                    val recorded = List(count) { server.takeRequest() }
                    assertEquals("GET", recorded.first().method)
                    assertEquals("/api/accounts/acme/threads/models", recorded.first().path)
                    assertEquals("/api/accounts/acme/$dialect/models", recorded[count - 2].path)
                    assertEquals(1, recorded.count { it.method != "GET" })
                    val suffix = when (operation) {
                        "create" -> ""
                        "send" -> "/t/messages"
                        "archive" -> "/t"
                        else -> "/t/$operation"
                    }
                    assertEquals("/api/accounts/acme/$dialect$suffix", recorded.last().path)
                    assertEquals(count, server.requestCount)
                }
            }
        }
    }

    @Test
    fun `non 404 read and probe errors never fallback or write`() = runTest {
        for (code in listOf(401, 403, 409, 500, 503)) {
            MockWebServer().use { server ->
                val api = ThreadTransport(Retrofit.Builder().baseUrl(server.url("/")).build(), moshi).api
                for (mutation in listOf(false, true)) {
                    server.enqueue(MockResponse().setResponseCode(code))
                    try {
                        if (mutation) api.create("acme", CreateThread("prompt", "chatgpt", "model")) else api.list("acme")
                        org.junit.Assert.fail("Expected HTTP $code")
                    } catch (error: HttpException) {
                        assertEquals(code, error.code())
                    }
                    assertEquals("GET", server.takeRequest().method)
                }
                assertEquals(2, server.requestCount)
            }
        }
    }

    @Test
    fun `both preview identifiers decode but missing malformed and null canonical identifiers fail`() = runTest {
        val preview = """{"head_sha":"head","base_sha":"base","diff":"patch","target_branch":"main",
            "mode":"direct","request_id":"request","thread_id":"t","account_id":12,
            "repository":"acme/private","sandbox_id":"sandbox","actor":"app"}"""
        for (dialect in listOf("threads", "jams")) {
            for (identifier in listOf("thread_id", "jam_id")) {
                val valid = preview.replace("thread_id", identifier)
                val bodies = listOf(
                    valid to "t",
                    valid.replace("\"$identifier\":\"t\",", "") to null,
                    valid.replace("\"t\"", "null") to null,
                    preview.replace("\"thread_id\":\"t\"", "\"thread_id\":null,\"jam_id\":\"legacy\"") to null,
                    preview.replace("\"thread_id\":\"t\"", "\"thread_id\":\"t\",\"jam_id\":\"legacy\"") to "t",
                )
                MockWebServer().use { server ->
                    val api = ThreadTransport(Retrofit.Builder().baseUrl(server.url("/")).build(), moshi).api
                    for ((body, expected) in bodies) {
                        if (dialect == "jams") server.enqueue(MockResponse().setResponseCode(404))
                        server.enqueue(MockResponse().setBody("""{"models":[],"errors":[]}"""))
                        server.enqueue(MockResponse().setBody(body))
                        try {
                            val actual = api.shipPreview("acme", "t").threadId
                            assertTrue("Malformed identifier accepted: $body", expected != null)
                            assertEquals(expected, actual)
                        } catch (_: JsonDataException) {
                            assertNull("Valid identifier rejected: $body", expected)
                        }
                        assertEquals("/api/accounts/acme/threads/models", server.takeRequest().path)
                        if (dialect == "jams") assertEquals("/api/accounts/acme/jams/models", server.takeRequest().path)
                        val request = server.takeRequest()
                        assertEquals("POST", request.method)
                        assertEquals("/api/accounts/acme/$dialect/t/ship-preview", request.path)
                    }
                    assertEquals(bodies.size * if (dialect == "jams") 3 else 2, server.requestCount)
                }
            }
        }
    }

    private fun requestBody(request: Request): String =
        Buffer().also { request.body!!.writeTo(it) }.readUtf8()
}
