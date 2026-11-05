package dev.tuist.app.data.aisubscriptions

import com.squareup.moshi.Moshi
import dev.tuist.app.api.AISubscriptionsApi
import dev.tuist.app.api.model.AISubscription1
import dev.tuist.app.api.model.ChatGPTSubscriptionLogin1
import dev.tuist.app.api.model.ConnectClaudeSubscriptionRequest
import dev.tuist.app.api.model.PollChatGPTSubscriptionLoginRequest
import retrofit2.Response
import javax.inject.Inject
import javax.inject.Singleton

/** A failure to manage AI subscriptions. [message] is the server's explanation, when it gave one. */
class AISubscriptionsException(message: String) : Exception(message)

/**
 * The signed-in user's personal Claude and ChatGPT subscriptions. Only the signed-in Tuist app can
 * manage them, and only for users with the `ai` feature flag.
 */
@Singleton
class AISubscriptionsRepository @Inject constructor(
    private val api: AISubscriptionsApi,
    private val moshi: Moshi,
) {
    suspend fun list(): List<AISubscription1> = api.listAISubscriptions().bodyOrThrow().subscriptions.supported()

    /** Saves the token `claude setup-token` prints. */
    suspend fun connectClaude(token: String): List<AISubscription1> =
        api.connectClaudeSubscription(ConnectClaudeSubscriptionRequest(token)).bodyOrThrow().subscriptions.supported()

    suspend fun startChatGPTLogin(): ChatGPTSubscriptionLogin1 = api.startChatGPTSubscriptionLogin().bodyOrThrow()

    /** Returns whether the user approved the sign-in. Poll no faster than the login's interval. */
    suspend fun pollChatGPTLogin(loginId: String): Boolean =
        api.pollChatGPTSubscriptionLogin(PollChatGPTSubscriptionLoginRequest(loginId)).bodyOrThrow().status == "connected"

    suspend fun cancelChatGPTLogin(loginId: String) {
        val response = api.cancelChatGPTSubscriptionLogin(loginId)
        if (!response.isSuccessful) throw response.error()
    }

    suspend fun disconnect(provider: String): List<AISubscription1> =
        api.disconnectAISubscription(provider).bodyOrThrow().subscriptions.supported()

    // Servers can add providers, which the app skips until it supports them.
    private fun List<AISubscription1>.supported() = filter { it.provider in SUPPORTED_PROVIDERS }

    private fun <T> Response<T>.bodyOrThrow(): T {
        val body = body()
        if (isSuccessful && body != null) return body
        throw error()
    }

    private fun <T> Response<T>.error(): AISubscriptionsException {
        val message = errorBody()?.string()?.let { json ->
            runCatching { moshi.adapter(dev.tuist.app.api.model.Error::class.java).fromJson(json)?.message }.getOrNull()
        }
        return AISubscriptionsException(
            message ?: "The AI subscriptions could not be updated due to an unknown Tuist response of ${code()}.",
        )
    }

    companion object {
        const val CLAUDE = "claude"
        const val CHATGPT = "chatgpt"
        private val SUPPORTED_PROVIDERS = setOf(CLAUDE, CHATGPT)
    }
}
