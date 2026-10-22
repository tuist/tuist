package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.logging.Logging
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.nio.channels.FileChannel
import java.nio.channels.OverlappingFileLockException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

internal enum class ReportKind(val path: String) {
    BUILD("gradle/builds"),
    TEST_RUN("tests");

    fun url(baseUrl: String, config: CacheConfiguration): URI =
        URI(baseUrl).resolve("/api/projects/${config.accountHandle}/${config.projectHandle}/$path")
}

internal class ReportPostResult(val status: Int, val body: String?) {
    val accepted: Boolean get() = status in 200..299
}

internal data class ReportOutboxEntry(
    val kind: ReportKind,
    val id: String,
    val url: String,
    @SerializedName("created_at_ms") val createdAtMs: Long,
    @SerializedName("actor_id") val actorId: String?,
    val body: String
)

/** Authenticated reports kept on disk until the server accepts or refuses them, so a later build can resend them. */
internal class ReportOutbox(
    private val directory: File,
    private val clock: () -> Long = System::currentTimeMillis,
    private val maxAgeMs: Long = TimeUnit.MINUTES.toMillis(45),
    private val maxEntries: Int = 50,
    private val maxBytes: Long = 50L * 1024 * 1024,
    private val maxReplays: Int = 5,
    private val replayBudgetMs: Long = 3_000
) {
    private val logger = Logging.getLogger(ReportOutbox::class.java)
    private val gson = Gson()

    fun deliver(entry: ReportOutboxEntry, post: () -> ReportPostResult): ReportPostResult {
        val file = write(entry)
        inFlight.add(entry.id)
        try {
            val result = post()
            if (file != null && isFinal(result.status)) delete(file)
            return result
        } finally {
            inFlight.remove(entry.id)
        }
    }

    fun replay(destinations: Set<String>, post: (ReportOutboxEntry, Long) -> ReportPostResult) {
        try {
            if (!directory.isDirectory) return
            withReplayLock { replayLocked(destinations, post) }
        } catch (e: Exception) {
            logger.debug("Tuist: Could not send earlier reports", e)
        }
    }

    private fun replayLocked(destinations: Set<String>, post: (ReportOutboxEntry, Long) -> ReportPostResult) {
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(replayBudgetMs)
        var attempted = 0
        var delivered = 0
        for (file in pendingFiles()) {
            if (attempted >= maxReplays || System.nanoTime() >= deadlineNanos) break
            val entry = read(file) ?: continue
            if (entry.url !in destinations || entry.id in inFlight) continue
            attempted++
            val result = try {
                post(entry, deadlineNanos)
            } catch (e: Exception) {
                logger.info("Tuist: An earlier report could not be sent yet: ${e.message}")
                break
            }
            if (!isFinal(result.status)) {
                logger.info("Tuist: An earlier report could not be sent yet (HTTP ${result.status})")
                break
            }
            delete(file)
            if (result.accepted) delivered++
        }
        if (delivered > 0) logger.info("Tuist: Sent $delivered earlier report(s)")
    }

    private fun write(entry: ReportOutboxEntry): File? = try {
        require(UUID_PATTERN.matches(entry.id)) { "Unexpected report id ${entry.id}" }
        val bytes = gson.toJson(entry).toByteArray(Charsets.UTF_8)
        if (bytes.size > maxBytes) {
            null
        } else {
            Files.createDirectories(directory.toPath())
            val file = File(directory, "${entry.createdAtMs}-${entry.id}$ENTRY_SUFFIX")
            val temporary = File(directory, "${file.name}.${UUID.randomUUID()}$TEMPORARY_SUFFIX")
            Files.write(temporary.toPath(), bytes)
            try {
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
            enforceBounds(keep = file)
            file
        }
    } catch (e: Exception) {
        logger.debug("Tuist: Could not persist the report before sending it", e)
        null
    }

    private fun enforceBounds(keep: File) {
        val files = pendingFiles()
        var count = files.size
        var bytes = files.sumOf { it.length() }
        for (file in files) {
            if (count <= maxEntries && bytes <= maxBytes) break
            if (file == keep) continue
            val size = file.length()
            delete(file)
            count--
            bytes -= size
        }
    }

    private fun pendingFiles(): List<File> {
        val now = clock()
        val pending = mutableListOf<Pair<Long, File>>()
        for (file in directory.listFiles().orEmpty()) {
            val name = file.name
            when {
                name.endsWith(TEMPORARY_SUFFIX) -> if (now - file.lastModified() > maxAgeMs) delete(file)
                name.endsWith(ENTRY_SUFFIX) -> {
                    val createdAtMs = ENTRY_NAME.matchEntire(name)?.groupValues?.get(1)?.toLongOrNull()
                    if (createdAtMs == null || now - createdAtMs > maxAgeMs || createdAtMs - now > maxAgeMs) {
                        delete(file)
                    } else {
                        pending.add(createdAtMs to file)
                    }
                }
            }
        }
        return pending.sortedWith(compareBy({ it.first }, { it.second.name })).map { it.second }
    }

    private fun read(file: File): ReportOutboxEntry? {
        val entry = try {
            file.reader(Charsets.UTF_8).use { gson.fromJson(it, ReportOutboxEntry::class.java) }
        } catch (_: java.io.FileNotFoundException) {
            return null
        } catch (_: Exception) {
            null
        }
        @Suppress("SENSELESS_COMPARISON")
        val valid = entry != null && entry.kind != null && entry.id != null && entry.url != null && entry.body != null &&
            file.name == "${entry.createdAtMs}-${entry.id}$ENTRY_SUFFIX"
        if (!valid) {
            delete(file)
            return null
        }
        return entry
    }

    private fun <T> withReplayLock(action: () -> T): T? {
        FileChannel.open(
            File(directory, REPLAY_LOCK).toPath(),
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE
        ).use { channel ->
            val lock = try {
                channel.tryLock()
            } catch (_: OverlappingFileLockException) {
                null
            } ?: return null
            return lock.use { action() }
        }
    }

    private fun delete(file: File) {
        try {
            Files.deleteIfExists(file.toPath())
        } catch (e: IOException) {
            logger.debug("Tuist: Could not delete ${file.name}", e)
        }
    }

    private fun isFinal(status: Int): Boolean =
        status in 200..299 || (status in 400..499 && status !in TRANSIENT_CLIENT_STATUSES)

    companion object {
        private const val ENTRY_SUFFIX = ".json"
        private const val TEMPORARY_SUFFIX = ".tmp"
        private const val REPLAY_LOCK = "replay.lock"
        private val TRANSIENT_CLIENT_STATUSES = setOf(401, 408, 429)
        private val UUID_PATTERN = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        private val ENTRY_NAME = Regex("(\\d+)-${UUID_PATTERN.pattern}\\.json")
        private val inFlight: MutableSet<String> = ConcurrentHashMap.newKeySet()

        fun directory(gradleUserHome: File): File = File(gradleUserHome, "tuist/report-outbox")
    }
}

internal fun publishReport(
    outbox: ReportOutbox?,
    httpClient: TuistHttpClient,
    config: CacheConfiguration,
    baseUrl: String,
    kind: ReportKind,
    id: String,
    createdAtMs: Long,
    body: String,
    actorId: String?,
    description: String
): ReportPostResult {
    val url = kind.url(baseUrl, config)
    val post = { postReport(httpClient, config, url, body, actorId, description) }
    if (outbox == null || config.token.isBlank()) return post()

    val result = outbox.deliver(ReportOutboxEntry(kind, id, url.toString(), createdAtMs, actorId, body), post)
    if (result.accepted) {
        val destinations = ReportKind.entries.map { it.url(baseUrl, config).toString() }.toSet()
        outbox.replay(destinations) { entry, deadlineNanos ->
            postReport(httpClient, config, URI(entry.url), entry.body, entry.actorId, "Earlier report", deadlineNanos)
        }
    }
    return result
}

internal fun postReport(
    httpClient: TuistHttpClient,
    config: CacheConfiguration,
    url: URI,
    body: String,
    actorId: String?,
    description: String,
    deadlineNanos: Long? = null
): ReportPostResult {
    val bytes = body.toByteArray(Charsets.UTF_8)
    return httpClient.retrying(description, replaySafe = true, deadlineNanos = deadlineNanos) {
        val connection = httpClient.openConnection(url, config)
        try {
            deadlineNanos?.let {
                val remainingMs = TimeUnit.NANOSECONDS.toMillis(it - System.nanoTime())
                if (remainingMs <= 0) throw java.io.InterruptedIOException("$description ran out of time")
                connection.connectTimeout = minOf(connection.connectTimeout.toLong(), remainingMs).toInt()
                connection.readTimeout = minOf(connection.readTimeout.toLong(), remainingMs).toInt()
            }
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            actorId?.let { connection.setRequestProperty(ActorIdentifier.HEADER, it) }
            connection.outputStream.use { it.write(bytes) }

            val status = connection.responseCode
            when {
                status in 200..299 -> ReportPostResult(status, connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() })
                status == HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                else -> {
                    val errorBody = try {
                        connection.errorStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
                    } catch (_: Exception) {
                        null
                    }
                    if (status in TuistRetry.RETRYABLE_STATUSES) {
                        throw TuistRetry.statusFailure(connection, status) {
                            IOException("$description failed with HTTP $status: ${errorBody ?: "(no response body)"}")
                        }
                    }
                    ReportPostResult(status, errorBody)
                }
            }
        } finally {
            connection.disconnect()
        }
    }
}
