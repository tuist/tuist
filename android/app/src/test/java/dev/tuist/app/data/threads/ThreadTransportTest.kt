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
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.Retrofit

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
                        requests.add(authenticated)
                        Response.Builder()
                            .request(authenticated)
                            .protocol(Protocol.HTTP_1_1)
                            .code(200)
                            .message("OK")
                            .body(response.toResponseBody("application/json".toMediaType()))
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

    private fun requestBody(request: Request): String =
        Buffer().also { request.body!!.writeTo(it) }.readUtf8()
}
