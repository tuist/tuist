package dev.tuist.atlas

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

// Only picker content streams and authenticated Rust downloads enter this boundary. Server filenames
// are display metadata, never filesystem paths; outgoing URIs identify short-lived random cache files.
object AtlasOrbitAttachments {
    const val MAX_BYTES = 5 * 1024 * 1024

    data class Picked(
        val filename: String,
        val contentType: String,
        val data: String,
    )

    private data class Grant(
        val context: Context,
        val file: File,
        val filename: String,
        val contentType: String,
        val expires: Long,
    )

    private val worker = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, ArrayBlockingQueue(2))
    private val grants = mutableMapOf<String, Grant>()

    fun validate(
        filename: String,
        contentType: String,
        size: Long,
    ) {
        require(filename.isNotBlank() && filename.codePointCount(0, filename.length) <= 255 && filename !in setOf(".", ".."))
        require(filename.none { it.isISOControl() || it == '/' || it == '\\' || it in '\u202a'..'\u202e' || it in '\u2066'..'\u2069' })
        require(contentType.length <= 127 && contentType.matches(Regex("[A-Za-z0-9!#\u0024&^_.+-]+/[A-Za-z0-9!#\u0024&^_.+-]+")))
        require(size in 1..MAX_BYTES.toLong())
    }

    internal fun readBounded(stream: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = stream.read(buffer, 0, minOf(buffer.size, MAX_BYTES + 1 - output.size()))
            if (count < 0) break
            require(count > 0) // A broken provider must not cause an unbounded read loop.
            output.write(buffer, 0, count)
            require(output.size() <= MAX_BYTES)
        }
        require(output.size() > 0)
        return output.toByteArray()
    }

    fun read(
        context: Context,
        uri: Uri,
        done: (Result<Picked>) -> Unit,
    ) = background(done) {
        require(uri.scheme == "content" && !uri.authority.isNullOrBlank() && uri.authority != "${context.packageName}.orbit-attachments")
        val resolver = context.contentResolver
        var name = "attachment"
        var reportedSize: Long? = null
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) reportedSize = cursor.getLong(sizeIndex)
            }
        }
        val type = resolver.getType(uri) ?: "application/octet-stream"
        validate(name, type, 1)
        require(reportedSize == null || reportedSize == -1L || reportedSize in 1..MAX_BYTES.toLong())
        val bytes = resolver.openInputStream(uri)?.use(::readBounded) ?: throw FileNotFoundException()
        validate(name, type, bytes.size.toLong())
        Picked(name, type, Base64.getEncoder().encodeToString(bytes))
    }

    fun cache(
        context: Context,
        value: JSONObject,
        done: (Result<Uri>) -> Unit,
    ) = background(done) {
        val name = value.getString("filename")
        val type = value.getString("content_type")
        val size = value.getLong("byte_size")
        validate(name, type, size)
        val data = value.getString("data")
        require(data.length <= ((MAX_BYTES + 2) / 3) * 4)
        val bytes = Base64.getDecoder().decode(data)
        require(bytes.size.toLong() == size)
        val directory = File(context.cacheDir, "orbit-attachments").apply { mkdirs() }
        val token = UUID.randomUUID().toString()
        val file = File(directory, token)
        try {
            file.outputStream().use { it.write(bytes) }
            synchronized(grants) {
                grants[token] = Grant(context.applicationContext, file, name, type, SystemClock.elapsedRealtime() + 300_000)
            }
        } catch (failure: Exception) {
            file.delete()
            throw failure
        }
        Handler(Looper.getMainLooper()).postDelayed({ remove(token) }, 300_000)
        Uri
            .Builder()
            .scheme("content")
            .authority("${context.packageName}.orbit-attachments")
            .appendPath(token)
            .build()
    }

    fun clear(context: Context? = null) {
        synchronized(grants) { grants.keys.toList() }.forEach(::remove)
        context?.let { File(it.cacheDir, "orbit-attachments").listFiles()?.forEach(File::delete) }
    }

    fun remove(uri: Uri) {
        uri.lastPathSegment?.let(::remove)
    }

    private fun remove(token: String) {
        val grant = synchronized(grants) { grants.remove(token) } ?: return
        grant.context.revokeUriPermission(
            Uri
                .Builder()
                .scheme("content")
                .authority("${grant.context.packageName}.orbit-attachments")
                .appendPath(token)
                .build(),
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )
        grant.file.delete()
    }

    private fun grant(uri: Uri): Grant {
        val token = uri.pathSegments.singleOrNull() ?: throw FileNotFoundException()
        val grant = synchronized(grants) { grants[token] } ?: throw FileNotFoundException()
        if (uri.authority != "${grant.context.packageName}.orbit-attachments" || grant.expires <= SystemClock.elapsedRealtime()) {
            remove(token)
            throw FileNotFoundException()
        }
        return grant
    }

    internal fun type(uri: Uri) = grant(uri).contentType

    internal fun query(
        uri: Uri,
        projection: Array<out String>?,
    ): Cursor {
        val grant = grant(uri)
        val columns =
            (projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)).filter {
                it == OpenableColumns.DISPLAY_NAME || it == OpenableColumns.SIZE
            }
        return MatrixCursor(columns.toTypedArray()).apply {
            addRow(columns.map { if (it == OpenableColumns.DISPLAY_NAME) grant.filename else grant.file.length() })
        }
    }

    internal fun open(uri: Uri) = ParcelFileDescriptor.open(grant(uri).file, ParcelFileDescriptor.MODE_READ_ONLY)

    private fun <T> background(
        done: (Result<T>) -> Unit,
        work: () -> T,
    ) {
        val main = Handler(Looper.getMainLooper())
        try {
            worker.execute {
                val result =
                    runCatching(work).recoverCatching {
                        throw IllegalStateException("Could not open this attachment. Use a file of at most 5 MiB and try again.")
                    }
                main.post { done(result) }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            main.post { done(Result.failure(IllegalStateException("Wait for the current attachment to finish."))) }
        }
    }
}

class AtlasOrbitAttachmentProvider : ContentProvider() {
    override fun onCreate() = true

    override fun getType(uri: Uri) = AtlasOrbitAttachments.type(uri)

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ) = AtlasOrbitAttachments.query(uri, projection)

    override fun openFile(
        uri: Uri,
        mode: String,
    ): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException()
        return AtlasOrbitAttachments.open(uri)
    }

    override fun insert(
        uri: Uri,
        values: ContentValues?,
    ): Uri? = throw UnsupportedOperationException()

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException()

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException()
}
