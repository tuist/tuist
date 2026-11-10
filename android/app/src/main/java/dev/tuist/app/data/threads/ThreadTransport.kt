package dev.tuist.app.data.threads

import com.squareup.moshi.Json
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import dev.tuist.app.data.auth.TokenStorage
import java.util.UUID
import javax.inject.Inject
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.HttpException
import retrofit2.converter.moshi.MoshiConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Uses the selected origin, authentication and TLS configuration without logging private
 * conversations.
 */
class ThreadTransport internal constructor(retrofit: Retrofit, moshi: Moshi, session: TokenStorage.Session? = null) {
    @Inject constructor(retrofit: Retrofit, moshi: Moshi, storage: TokenStorage) : this(retrofit, moshi, storage.snapshot())

    private val client =
        (retrofit.callFactory() as OkHttpClient)
            .newBuilder()
            .apply {
                interceptors().removeAll { it is HttpLoggingInterceptor }
                networkInterceptors().removeAll { it is HttpLoggingInterceptor }
                if (session != null) interceptors().add(0, okhttp3.Interceptor { chain ->
                    chain.proceed(chain.request().newBuilder().tag(TokenStorage.Session::class.java, session).build())
                })
            }
            .build()

    val api: ThreadsApi =
        retrofit
            .newBuilder()
            .apply {
                client(client)
                converterFactories()
                    .add(0, MoshiConverterFactory.create(moshi.newBuilder().add(ThreadAliases).build()).withNullSerialization())
            }
            .build()
            .create(ThreadRoutes::class.java)
            .let { CompatibleThreadsApi(it) }

    internal suspend fun dialect(account: String): String = (api as CompatibleThreadsApi).dialect(account)
}

interface ThreadsApi {
    suspend fun list(account: String, cursor: String? = null): ThreadPage
    suspend fun repositories(account: String): ThreadRepositories
    suspend fun models(account: String): ThreadModelCatalog
    suspend fun history(account: String, id: String, before: Int? = null): ServerThread
    suspend fun create(account: String, body: CreateThread): ServerThread
    suspend fun send(account: String, id: String, body: SendMessage): ServerThread
    suspend fun archive(account: String, id: String, body: ArchiveThread): ServerThread
    suspend fun shipPreview(account: String, id: String): ShipPreview
    suspend fun ship(account: String, id: String, approval: ShipApproval): ServerThread
}

private class CompatibleThreadsApi(private val routes: ThreadRoutes) : ThreadsApi {
    // Only safe reads negotiate the legacy dialect; never replay a write after a 404.
    private suspend fun <T> read(operation: suspend (String) -> T): T =
        try {
            operation("threads")
        } catch (error: HttpException) {
            if (error.code() != 404) throw error
            operation("jams")
        }

    suspend fun dialect(account: String): String = read { dialect ->
        routes.models(account, dialect)
        dialect
    }

    override suspend fun list(account: String, cursor: String?) = read { routes.list(account, it, cursor) }
    override suspend fun repositories(account: String) = read { routes.repositories(account, it) }
    override suspend fun models(account: String) = read { routes.models(account, it) }
    override suspend fun history(account: String, id: String, before: Int?) = read { routes.history(account, it, id, before) }
    override suspend fun create(account: String, body: CreateThread) = routes.create(account, dialect(account), body)
    override suspend fun send(account: String, id: String, body: SendMessage) = routes.send(account, dialect(account), id, body)
    override suspend fun archive(account: String, id: String, body: ArchiveThread) = routes.archive(account, dialect(account), id, body)
    override suspend fun shipPreview(account: String, id: String) = routes.shipPreview(account, dialect(account), id)
    override suspend fun ship(account: String, id: String, approval: ShipApproval) = routes.ship(account, dialect(account), id, approval)
}

// Normalize only known aliases, then let the required-field adapters validate the payload.
private object ThreadAliases : JsonAdapter.Factory {
    override fun create(type: java.lang.reflect.Type, annotations: Set<Annotation>, moshi: Moshi): JsonAdapter<*>? {
        val keys = when (type) {
            ThreadPage::class.java -> "threads" to "jams"
            ShipPreview::class.java -> "thread_id" to "jam_id"
            else -> return null
        }
        val delegate = moshi.nextAdapter<Any>(this, type, annotations)
        return object : JsonAdapter<Any>() {
            override fun fromJson(reader: com.squareup.moshi.JsonReader): Any? {
                val value = reader.readJsonValue()
                if (value is Map<*, *> && !value.containsKey(keys.first) && value.containsKey(keys.second)) {
                    val normalized = value.toMutableMap()
                    normalized[keys.first] = value[keys.second]
                    return delegate.fromJsonValue(normalized)
                }
                return delegate.fromJsonValue(value)
            }
            override fun toJson(writer: com.squareup.moshi.JsonWriter, value: Any?) = delegate.toJson(writer, value)
        }
    }
}

internal interface ThreadRoutes {
    @GET("api/accounts/{account}/{dialect}")
    suspend fun list(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Query("cursor") cursor: String? = null,
    ): ThreadPage

    @GET("api/accounts/{account}/{dialect}/repositories")
    suspend fun repositories(@Path("account") account: String, @Path("dialect") dialect: String): ThreadRepositories

    @GET("api/accounts/{account}/{dialect}/models")
    suspend fun models(@Path("account") account: String, @Path("dialect") dialect: String): ThreadModelCatalog

    @GET("api/accounts/{account}/{dialect}/{id}")
    suspend fun history(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Path("id") id: String,
        @Query("before") before: Int? = null,
    ): ServerThread

    @POST("api/accounts/{account}/{dialect}")
    suspend fun create(@Path("account") account: String, @Path("dialect") dialect: String, @Body body: CreateThread): ServerThread

    @POST("api/accounts/{account}/{dialect}/{id}/messages")
    suspend fun send(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Path("id") id: String,
        @Body body: SendMessage,
    ): ServerThread

    @PATCH("api/accounts/{account}/{dialect}/{id}")
    suspend fun archive(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Path("id") id: String,
        @Body body: ArchiveThread,
    ): ServerThread

    @POST("api/accounts/{account}/{dialect}/{id}/ship-preview")
    suspend fun shipPreview(@Path("account") account: String, @Path("dialect") dialect: String, @Path("id") id: String): ShipPreview

    // Calling this is a separate application-owned approval, never a model tool or suggested
    // prompt.
    @POST("api/accounts/{account}/{dialect}/{id}/ship")
    suspend fun ship(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Path("id") id: String,
        @Body approval: ShipApproval,
    ): ServerThread
}

data class ThreadPage(
    val threads: List<ServerThread>,
    @Json(name = "next_cursor") val nextCursor: String? = null,
)

data class ThreadRepositories(val repositories: List<ThreadRepository>)

data class ThreadModelCatalog(val models: List<ThreadModel>, val errors: List<ThreadModelError>)

data class ThreadModel(val provider: String, val id: String, val name: String)

data class ThreadModelError(val provider: String, val code: String)

data class ThreadRepository(
    @Json(name = "full_name") val fullName: String,
    @Json(name = "default_branch") val defaultBranch: String,
)

data class CreateThread(
    val content: String,
    val provider: String,
    val model: String,
    val repository: String? = null,
    @Json(name = "base_branch") val baseBranch: String? = null,
    @Json(name = "request_id") val requestId: String = UUID.randomUUID().toString(),
)

data class SendMessage(
    val content: String,
    @Json(name = "request_id") val requestId: String = UUID.randomUUID().toString(),
)

data class ArchiveThread(val status: String) {
    init {
        require(status == "active" || status == "archived")
    }
}

data class ShipPreview(
    @Json(name = "head_sha") val headSha: String,
    @Json(name = "base_sha") val baseSha: String,
    val diff: String,
    @Json(name = "target_branch") val targetBranch: String,
    val mode: String,
    @Json(name = "request_id") val requestId: String,
    @Json(name = "thread_id") val threadId: String,
    @Json(name = "account_id") val accountId: Long,
    val repository: String,
    @Json(name = "sandbox_id") val sandboxId: String,
    val actor: String,
)

data class ShipApproval(
    @Json(name = "request_id") val requestId: String,
    @Json(name = "head_sha") val headSha: String,
    @Json(name = "base_sha") val baseSha: String,
    @Json(name = "target_branch") val targetBranch: String,
    val mode: String,
) {
    constructor(
        preview: ShipPreview
    ) : this(
        requestId = preview.requestId,
        headSha = preview.headSha,
        baseSha = preview.baseSha,
        targetBranch = preview.targetBranch,
        mode = preview.mode,
    )
}

data class ServerThread(
    val id: String,
    val title: String,
    val goal: String,
    val repository: String,
    val branch: String,
    val profile: String,
    val provider: String? = null,
    val model: String? = null,
    val status: String,
    val visibility: String,
    val messages: List<ThreadMessage>,
    val diff: String,
    val revision: Int? = null,
    @Json(name = "archive_status") val archiveStatus: String? = null,
    @Json(name = "has_more") val hasMore: Boolean? = null,
    @Json(name = "next_before") val nextBefore: Int? = null,
)

data class ThreadMessage(
    val id: String,
    val role: String,
    val content: String,
    val position: Int? = null,
    val suggestions: List<String>? = null,
    val toolName: String? = null,
    val toolStatus: String? = null,
    val toolInput: String? = null,
    val parentMessageID: String? = null,
    // Presentation extensions are not emitted by the current server and must not hide history if
    // unsupported.
    val richContent: Any? = null,
    val createdAt: String? = null,
)
