package dev.tuist.app.data.jams

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
class JamTransport internal constructor(retrofit: Retrofit, moshi: Moshi, session: TokenStorage.Session? = null) {
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

    val api: JamsApi =
        retrofit
            .newBuilder()
            .apply {
                client(client)
                converterFactories()
                    .add(0, MoshiConverterFactory.create(moshi.newBuilder().add(JamAliases).build()).withNullSerialization())
            }
            .build()
            .create(JamRoutes::class.java)
            .let { CompatibleJamsApi(it) }

    internal suspend fun dialect(account: String): String = (api as CompatibleJamsApi).dialect(account)
}

interface JamsApi {
    suspend fun list(account: String, cursor: String? = null): JamPage
    suspend fun repositories(account: String): JamRepositories
    suspend fun models(account: String): JamModelCatalog
    suspend fun history(account: String, id: String, before: Int? = null): ServerJam
    suspend fun create(account: String, body: CreateJam): ServerJam
    suspend fun send(account: String, id: String, body: SendMessage): ServerJam
    suspend fun archive(account: String, id: String, body: ArchiveJam): ServerJam
    suspend fun shipPreview(account: String, id: String): ShipPreview
    suspend fun ship(account: String, id: String, approval: ShipApproval): ServerJam
}

private class CompatibleJamsApi(private val routes: JamRoutes) : JamsApi {
    private suspend fun <T> read(operation: suspend (String) -> T): T =
        try {
            operation("jams")
        } catch (error: HttpException) {
            if (error.code() != 404) throw error
            operation("threads")
        }

    suspend fun dialect(account: String): String = read { dialect ->
        routes.models(account, dialect)
        dialect
    }

    override suspend fun list(account: String, cursor: String?) = read { routes.list(account, it, cursor) }
    override suspend fun repositories(account: String) = read { routes.repositories(account, it) }
    override suspend fun models(account: String) = read { routes.models(account, it) }
    override suspend fun history(account: String, id: String, before: Int?) = read { routes.history(account, it, id, before) }
    override suspend fun create(account: String, body: CreateJam) = routes.create(account, dialect(account), body)
    override suspend fun send(account: String, id: String, body: SendMessage) = routes.send(account, dialect(account), id, body)
    override suspend fun archive(account: String, id: String, body: ArchiveJam) = routes.archive(account, dialect(account), id, body)
    override suspend fun shipPreview(account: String, id: String) = routes.shipPreview(account, dialect(account), id)
    override suspend fun ship(account: String, id: String, approval: ShipApproval) = routes.ship(account, dialect(account), id, approval)
}

// Normalize only known aliases, then let the required-field adapters validate the payload.
private object JamAliases : JsonAdapter.Factory {
    override fun create(type: java.lang.reflect.Type, annotations: Set<Annotation>, moshi: Moshi): JsonAdapter<*>? {
        val keys = when (type) {
            JamPage::class.java -> "jams" to "threads"
            ShipPreview::class.java -> "jam_id" to "thread_id"
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

internal interface JamRoutes {
    @GET("api/accounts/{account}/{dialect}")
    suspend fun list(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Query("cursor") cursor: String? = null,
    ): JamPage

    @GET("api/accounts/{account}/{dialect}/repositories")
    suspend fun repositories(@Path("account") account: String, @Path("dialect") dialect: String): JamRepositories

    @GET("api/accounts/{account}/{dialect}/models")
    suspend fun models(@Path("account") account: String, @Path("dialect") dialect: String): JamModelCatalog

    @GET("api/accounts/{account}/{dialect}/{id}")
    suspend fun history(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Path("id") id: String,
        @Query("before") before: Int? = null,
    ): ServerJam

    @POST("api/accounts/{account}/{dialect}")
    suspend fun create(@Path("account") account: String, @Path("dialect") dialect: String, @Body body: CreateJam): ServerJam

    @POST("api/accounts/{account}/{dialect}/{id}/messages")
    suspend fun send(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Path("id") id: String,
        @Body body: SendMessage,
    ): ServerJam

    @PATCH("api/accounts/{account}/{dialect}/{id}")
    suspend fun archive(
        @Path("account") account: String,
        @Path("dialect") dialect: String,
        @Path("id") id: String,
        @Body body: ArchiveJam,
    ): ServerJam

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
    ): ServerJam
}

data class JamPage(
    val jams: List<ServerJam>,
    @Json(name = "next_cursor") val nextCursor: String? = null,
)

data class JamRepositories(val repositories: List<JamRepository>)

data class JamModelCatalog(val models: List<JamModel>, val errors: List<JamModelError>)

data class JamModel(val provider: String, val id: String, val name: String)

data class JamModelError(val provider: String, val code: String)

data class JamRepository(
    @Json(name = "full_name") val fullName: String,
    @Json(name = "default_branch") val defaultBranch: String,
)

data class CreateJam(
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

data class ArchiveJam(val status: String) {
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
    @Json(name = "jam_id") val jamId: String,
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

data class ServerJam(
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
    val messages: List<JamMessage>,
    val diff: String,
    val revision: Int? = null,
    @Json(name = "archive_status") val archiveStatus: String? = null,
    @Json(name = "has_more") val hasMore: Boolean? = null,
    @Json(name = "next_before") val nextBefore: Int? = null,
)

data class JamMessage(
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
