package dev.tuist.app.data.network

import dev.tuist.app.data.auth.TokenStorage
import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException
import javax.inject.Inject

class SessionGuardInterceptor @Inject constructor(private val tokens: TokenStorage) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val session = chain.request().tag(TokenStorage.Session::class.java)
        val discovery = chain.request().tag(ProfileRequest::class.java)
        if (discovery != null) {
            if (tokens.credentials(discovery.profileId) == null) throw IOException("Login removed")
        } else if (session != null && !tokens.isCurrent(session)) throw IOException("Authentication profile changed")
        return chain.proceed(chain.request())
    }
}
