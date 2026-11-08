package dev.tuist.app.data.jams

import com.squareup.moshi.Json
import com.squareup.moshi.Moshi
import dev.tuist.app.data.auth.TokenStorage
import java.util.UUID
import javax.inject.Inject
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
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
                    .add(0, MoshiConverterFactory.create(moshi).withNullSerialization())
            }
            .build()
            .create(JamsApi::class.java)
}

interface JamsApi {
    @GET("api/accounts/{account}/jams")
    suspend fun list(
        @Path("account") account: String,
        @Query("cursor") cursor: String? = null,
    ): JamPage

    @GET("api/accounts/{account}/jams/repositories")
    suspend fun repositories(@Path("account") account: String): JamRepositories

    @GET("api/accounts/{account}/jams/models")
    suspend fun models(@Path("account") account: String): JamModelCatalog

    @GET("api/accounts/{account}/jams/{id}")
    suspend fun history(
        @Path("account") account: String,
        @Path("id") id: String,
        @Query("before") before: Int? = null,
    ): ServerJam

    @POST("api/accounts/{account}/jams")
    suspend fun create(@Path("account") account: String, @Body body: CreateJam): ServerJam

    @POST("api/accounts/{account}/jams/{id}/messages")
    suspend fun send(
        @Path("account") account: String,
        @Path("id") id: String,
        @Body body: SendMessage,
    ): ServerJam

    @PATCH("api/accounts/{account}/jams/{id}")
    suspend fun archive(
        @Path("account") account: String,
        @Path("id") id: String,
        @Body body: ArchiveJam,
    ): ServerJam

    @POST("api/accounts/{account}/jams/{id}/ship-preview")
    suspend fun shipPreview(@Path("account") account: String, @Path("id") id: String): ShipPreview

    // Calling this is a separate application-owned approval, never a model tool or suggested
    // prompt.
    @POST("api/accounts/{account}/jams/{id}/ship")
    suspend fun ship(
        @Path("account") account: String,
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
