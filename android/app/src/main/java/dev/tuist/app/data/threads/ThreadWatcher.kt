package dev.tuist.app.data.threads

import com.squareup.moshi.Moshi
import dev.tuist.app.data.auth.TokenStorage
import java.io.IOException
import java.util.Base64
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.Authenticator
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.logging.HttpLoggingInterceptor
import okio.ByteString
import retrofit2.Retrofit

/** Foreground-scoped Phoenix invalidations; HTTP remains the authoritative conversation state. */
class ThreadWatcher
internal constructor(
    private val retrofit: Retrofit,
    moshi: Moshi,
    private val authorize: suspend (String) -> Unit,
    private val token: () -> String?,
    private val openSocket: (OkHttpClient, Request, WebSocketListener) -> WebSocket =
        { client, request, listener ->
            client.newWebSocket(request, listener)
        },
) {
    @Inject
    constructor(
        retrofit: Retrofit,
        moshi: Moshi,
        storage: TokenStorage,
        transport: ThreadTransport,
    ) : this(
        retrofit,
        moshi,
        { account ->
            transport.api.list(account)
            Unit
        },
        storage::getAccessToken,
    )

    private val frames = moshi.adapter(List::class.java)
    private val client =
        (retrofit.callFactory() as OkHttpClient)
            .newBuilder()
            .apply {
                interceptors().removeAll { it is HttpLoggingInterceptor }
                networkInterceptors().removeAll { it is HttpLoggingInterceptor }
                // A 401 must rebuild the bearer subprotocol, not retry with only a refreshed
                // Authorization header.
                authenticator(Authenticator.NONE)
            }
            .build()

    suspend fun watch(
        account: String,
        threadId: String?,
        invalidate: suspend () -> Unit,
        disconnected: suspend () -> Unit,
    ) {
        var attempt = 0
        while (currentCoroutineContext().isActive) {
            try {
                authorize(account)
                val credential =
                    token()?.takeIf { it.isNotEmpty() } ?: throw IOException("Missing credentials")
                connection(account, threadId, credential, invalidate)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                disconnected()
                attempt = (attempt + 1).coerceAtMost(5)
                delay(1_000L shl attempt)
            }
        }
    }

    private suspend fun connection(
        account: String,
        threadId: String?,
        credential: String,
        invalidate: suspend () -> Unit,
    ) = coroutineScope {
        val events = Channel<Event>(Channel.BUFFERED)
        fun enqueue(event: Event) {
            if (!events.trySend(event).isSuccess) events.close(IOException("Socket event overflow"))
        }
        val request =
            Request.Builder()
                .url(
                    retrofit
                        .baseUrl()
                        .newBuilder()
                        .addPathSegments("threads/socket/websocket")
                        .query(null)
                        .addQueryParameter("vsn", "2.0.0")
                        .build()
                )
                .header(
                    "Sec-WebSocket-Protocol",
                    "phoenix, base64url.bearer.phx." +
                        Base64.getUrlEncoder()
                            .withoutPadding()
                            .encodeToString(credential.toByteArray(Charsets.UTF_8)),
                )
                .build()
        val socket =
            openSocket(
                client,
                request,
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) =
                        enqueue(Event.Open)

                    override fun onMessage(webSocket: WebSocket, text: String) =
                        enqueue(Event.Message(text))

                    override fun onMessage(webSocket: WebSocket, bytes: ByteString) =
                        enqueue(Event.Message(bytes.utf8()))

                    override fun onFailure(
                        webSocket: WebSocket,
                        t: Throwable,
                        response: Response?,
                    ) = enqueue(Event.Lost)

                    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) =
                        enqueue(Event.Lost)

                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) =
                        enqueue(Event.Lost)
                },
            )
        val topic = "threads:$account:${threadId ?: "inbox"}"
        val joinRef = "1"
        var nextRef = 1L
        var pending: String? = joinRef
        var joined = false
        val heartbeat = launch {
            delay(10_000)
            while (isActive) {
                events.send(Event.Tick)
                delay(20_000)
            }
        }
        fun send(join: String?, ref: String, target: String, event: String) {
            if (
                !socket.send(
                    frames.toJson(listOf(join, ref, target, event, emptyMap<String, Any>()))
                )
            ) {
                throw IOException("Socket send failed")
            }
        }
        try {
            for (event in events) {
                when (event) {
                    Event.Open -> send(joinRef, joinRef, topic, "phx_join")
                    Event.Lost -> throw IOException("Socket disconnected")
                    Event.Tick -> {
                        if (pending != null) throw IOException("Socket acknowledgement timed out")
                        val ref = (++nextRef).toString()
                        pending = ref
                        send(null, ref, "phoenix", "heartbeat")
                    }
                    is Event.Message -> {
                        val frame =
                            try {
                                frames.fromJson(event.text)
                            } catch (_: Exception) {
                                null
                            }
                        if (frame == null || frame.size != 5) continue
                        val frameTopic = frame[2]
                        val name = frame[3]
                        val payload = frame[4] as? Map<*, *>
                        if (
                            frameTopic == "phoenix" &&
                                frame[0] == null &&
                                name == "phx_reply" &&
                                joined &&
                                pending != null &&
                                frame[1] == pending &&
                                payload?.get("status") == "ok"
                        ) {
                            pending = null
                        }
                        if (frameTopic != topic || (frame[0] != null && frame[0] != joinRef))
                            continue
                        when (name) {
                            "phx_error",
                            "phx_close" -> throw IOException("Channel disconnected")
                            "phx_reply" ->
                                if (!joined && frame[0] == joinRef && frame[1] == joinRef) {
                                    if (payload?.get("status") != "ok")
                                        throw IOException("Channel join rejected")
                                    joined = true
                                    pending = null
                                    invalidate()
                                }
                            "snapshot" -> if (joined) invalidate()
                        }
                    }
                }
            }
        } finally {
            heartbeat.cancel()
            events.cancel()
            socket.close(1000, null)
            socket.cancel()
        }
    }

    private sealed interface Event {
        data object Open : Event

        data object Lost : Event

        data object Tick : Event

        data class Message(val text: String) : Event
    }
}
