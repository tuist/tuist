package dev.tuist.app.data.network

import dev.tuist.app.data.auth.TokenStorage
import okhttp3.Interceptor
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okio.Buffer
import okio.ForwardingSource
import okio.buffer
import javax.inject.Inject

class AuthInterceptor @Inject constructor(
    private val tokenStorage: TokenStorage,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val discovery = request.tag(ProfileRequest::class.java)
        val (session, token) = synchronized(tokenStorage) {
            if (discovery != null) {
                val credentials = tokenStorage.credentials(discovery.profileId) ?: throw java.io.IOException("Login removed")
                TokenStorage.Session(credentials.profileId, -1, origin = credentials.server) to credentials.access
            } else {
                request.tag(TokenStorage.Session::class.java)?.let {
                    if (!tokenStorage.isCurrent(it)) throw java.io.IOException("Authentication profile changed")
                }
                tokenStorage.snapshot() to tokenStorage.getAccessToken()
            }
        }
        fun valid() = if (discovery != null) tokenStorage.credentials(discovery.profileId) != null else tokenStorage.isCurrent(session)
        val origin = session.origin?.toHttpUrl() ?: request.url
        val path = request.url.pathSegments
        val scopedAccount = when {
            path.size >= 4 && path.take(2) == listOf("api", "accounts") && path[3] in listOf("jams", "threads") -> path[2]
            else -> null
        }
        if (discovery == null && scopedAccount != null) {
            val account = token?.let { dev.tuist.app.data.auth.JwtParser.parseAccount(it)?.handle }
            if (account != null && scopedAccount != account) throw java.io.IOException("Organization changed")
        }

        val authenticatedRequest = if (token != null) {
            request.newBuilder()
                .url(request.url.newBuilder().scheme(origin.scheme).host(origin.host).port(origin.port).build())
                .tag(TokenStorage.Session::class.java, session)
                .header("Authorization", "Bearer $token")
                .build()
        } else {
            request
        }

        val response = chain.proceed(authenticatedRequest)
        if (!valid()) {
            response.close()
            throw java.io.IOException("Authentication profile changed")
        }
        val body = response.body ?: return response
        val guardedSource = object : ForwardingSource(body.source()) {
            override fun read(sink: Buffer, byteCount: Long): Long {
                if (!valid()) throw java.io.IOException("Authentication profile changed")
                val count = super.read(sink, byteCount)
                if (!valid()) throw java.io.IOException("Authentication profile changed")
                return count
            }
        }.buffer()
        return response.newBuilder().body(object : ResponseBody() {
            override fun contentType() = body.contentType()
            override fun contentLength() = body.contentLength()
            override fun source() = guardedSource
        }).build()
    }
}

/** Explicit opt-in for membership discovery; never switches the foreground session. */
data class ProfileRequest(val profileId: String)
