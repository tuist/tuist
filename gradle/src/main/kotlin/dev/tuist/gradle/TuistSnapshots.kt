package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.annotations.SerializedName
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.gradle.api.Action
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.Directory
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.logging.Logging
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.Provider
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import org.gradle.api.tasks.TaskProvider
import org.gradle.api.tasks.testing.Test
import org.gradle.work.DisableCachingByDefault
import java.io.DataInputStream
import java.io.File
import java.io.IOException
import java.net.URI
import java.security.MessageDigest

/**
 * Registers `tuistUploadSnapshots`, which uploads the images a snapshot library recorded as a
 * Tuist snapshot build, and runs it after the Roborazzi and Paparazzi record tasks. In projects
 * that apply Paparazzi, it also generates a test that snapshots every Compose `@Preview`, and in
 * CI the debug unit test tasks, which render it, upload too, as `tuist test` does for Xcode.
 */
class TuistSnapshotsPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        val config = TuistGradleConfig.from(project) ?: return
        val snapshots = config.snapshots ?: return
        val previewsDirectory = project.layout.buildDirectory.dir("tuist/snapshots")
        val upload = project.tasks.register("tuistUploadSnapshots", TuistUploadSnapshots::class.java) {
            group = "tuist"
            description = "Uploads the recorded snapshot images to Tuist and compares them with their baseline."
            val paparazzi = project.pluginManager.hasPlugin("app.cash.paparazzi")
            when {
                snapshots.directory != null -> snapshotsDirectory.set(project.layout.projectDirectory.dir(snapshots.directory))
                paparazzi && snapshots.generatePreviewTests -> snapshotsDirectory.set(previewsDirectory)
                paparazzi -> snapshotsDirectory.set(project.layout.projectDirectory.dir("src/test/snapshots/images"))
                else -> snapshotsDirectory.set(project.layout.buildDirectory.dir("outputs/roborazzi"))
            }
            snapshots.diffThreshold?.let { diffThreshold.set(it) }
            setName.set(snapshots.set ?: project.path.removePrefix(":").ifEmpty { project.name }.replace(':', '/'))
            failOnChanges.set(snapshots.failOnChanges)
            serverUrl.set(config.url)
            config.project?.let { tuistProject.set(it) }
            useEnvironmentProxy.set(config.network.proxy)
            projectDirectory.set(project.layout.projectDirectory)
            rootDirectory.set(project.isolated.rootProject.projectDirectory)
        }
        // Lazy: only record tasks the build actually schedules are configured.
        project.tasks.configureEach {
            if (name.startsWith("recordRoborazzi") || name.startsWith("recordPaparazzi")) finalizedBy(upload)
        }
        if (snapshots.generatePreviewTests) {
            project.pluginManager.withPlugin("app.cash.paparazzi") {
                generatePreviewTests(project, snapshots, previewsDirectory, upload.takeIf { uploadsAfterUnitTests(project) })
            }
        }
    }

    /**
     * Whether the unit test tasks that render the generated preview tests upload them: in CI, unless
     * `-Ptuist.snapshots=false`. `-Ptuist.snapshots=true` also uploads locally, where it is off
     * because a local run would upload uncommitted changes and fail on them.
     */
    private fun uploadsAfterUnitTests(project: Project): Boolean =
        project.providers.gradleProperty(SNAPSHOTS_PROPERTY).orNull?.toBooleanStrictOrNull()
            ?: EnvironmentCIDetector().isCi()

    private fun generatePreviewTests(
        project: Project,
        snapshots: TuistGradleConfig.Snapshots,
        output: Provider<Directory>,
        upload: TaskProvider<TuistUploadSnapshots>?
    ) {
        project.dependencies.add("testImplementation", "io.github.sergio-sastre.ComposablePreviewScanner:android:$COMPOSABLE_PREVIEW_SCANNER_VERSION")
        // AGP lives in the project's classloader, so its variant API is called reflectively, as in TuistPreviews.
        val android = project.extensions.getByName("androidComponents")
        android.androidCall("onVariants", android.androidCall("selector").androidCall("all"), Action<Any> {
            val variant = this
            val unitTest = variant.androidCall("getUnitTest").takeIf { it != Unit } ?: return@Action
            val name = (variant.androidCall("getName") as String).replaceFirstChar { it.uppercaseChar() }
            @Suppress("UNCHECKED_CAST")
            val namespace = variant.androidCall("getNamespace") as Provider<String>
            val generate = project.tasks.register("tuistGenerate${name}PreviewSnapshotTest", TuistGeneratePreviewSnapshotTest::class.java) {
                description = "Generates the Paparazzi test that snapshots every Compose @Preview."
                packageTrees.set(if (snapshots.previewPackageTrees.isEmpty()) namespace.map { listOf(it) } else project.provider { snapshots.previewPackageTrees })
                includePrivatePreviews.set(snapshots.includePrivatePreviews)
                theme.set(snapshots.previewTheme ?: PAPARAZZI_DEFAULT_THEME)
                outputDirectory.set(project.layout.buildDirectory.dir("generated/tuist/snapshots/$name"))
            }
            // The Kotlin plugin compiles generated `java` directories, but not generated `kotlin` ones.
            unitTest.androidCall("getSources").androidCall("getJava")
                .androidCall("addGeneratedSourceDirectory", generate, { task: TuistGeneratePreviewSnapshotTest -> task.outputDirectory })
        })
        // Only Tuist's unit test JVMs write the images, so plain test runs leave no files behind.
        project.tasks.withType(Test::class.java).configureEach {
            if (!name.endsWith("UnitTest")) return@configureEach
            val directory = output.get().asFile
            outputs.dir(directory)
            systemProperty("tuist.snapshots.outputDir", directory.absolutePath)
            doFirst { directory.deleteRecursively() }
            // One build type, so `./gradlew test` uploads each preview once. Runs that render no
            // previews, such as ones filtered to other tests, upload nothing.
            if (upload != null && name.endsWith("DebugUnitTest")) finalizedBy(upload)
        }
        upload?.configure { mustRunAfter(project.tasks.withType(Test::class.java)) }
    }

    companion object {
        const val SNAPSHOTS_PROPERTY = "tuist.snapshots"
        const val COMPOSABLE_PREVIEW_SCANNER_VERSION = "0.8.2"
        const val PAPARAZZI_DEFAULT_THEME = "android:Theme.Material.NoActionBar.Fullscreen"
    }
}

/** Writes the generated preview snapshot test from the template bundled with the plugin. */
@CacheableTask
abstract class TuistGeneratePreviewSnapshotTest : DefaultTask() {
    @get:Input abstract val packageTrees: ListProperty<String>
    @get:Input abstract val includePrivatePreviews: Property<Boolean>
    @get:Input abstract val theme: Property<String>
    @get:OutputDirectory abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val template = TuistGeneratePreviewSnapshotTest::class.java.getResource("TuistPreviewSnapshotTest.kt.template")!!.readText()
        val source = template
            .replace("__PACKAGE_TREES__", packageTrees.get().joinToString(", ") { kotlinString(it) })
            .replace("__INCLUDE_PRIVATE__", if (includePrivatePreviews.get()) "\n                .includePrivatePreviews()" else "")
            .replace("__THEME__", kotlinString(theme.get()))
        val directory = outputDirectory.get().asFile
        directory.deleteRecursively()
        File(directory, "dev/tuist/snapshots").apply { mkdirs() }.resolve("TuistPreviewSnapshotTest.kt").writeText(source)
    }

    private fun kotlinString(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("$", "\\$") + "\""
}

@DisableCachingByDefault(because = "Uploading is a side effect; the server deduplicates images by content")
abstract class TuistUploadSnapshots : DefaultTask() {
    @get:Internal abstract val snapshotsDirectory: DirectoryProperty
    @get:Input abstract val setName: Property<String>
    @get:Input abstract val failOnChanges: Property<Boolean>
    @get:Input @get:Optional abstract val diffThreshold: Property<Double>
    @get:Input abstract val serverUrl: Property<String>
    @get:Input @get:Optional abstract val tuistProject: Property<String>
    @get:Input abstract val useEnvironmentProxy: Property<Boolean>
    @get:Internal abstract val projectDirectory: DirectoryProperty
    @get:Internal abstract val rootDirectory: DirectoryProperty

    @TaskAction
    fun upload() {
        val directory = snapshotsDirectory.get().asFile
        val images = SnapshotImages.collect(directory)
        val allImageNames = SnapshotImages.allImageNames(directory)
        if (images.isEmpty()) {
            logger.lifecycle("Tuist: No snapshot images in ${directory.relativeTo(projectDirectory.get().asFile)}; nothing to upload.")
            return
        }
        val httpClients = TuistHttpClients(useEnvironmentProxy = useEnvironmentProxy.get())
        val httpClient = TuistHttpClient(
            ServerConfigurationProvider(tuistProject.orNull, serverUrl.get(), projectDirectory.get().asFile, httpClients),
            httpClients
        )
        val root = rootDirectory.get().asFile
        val git = SnapshotGitContext.read(root, httpClient, serverUrl.get())
        if (git.commitSha == null) {
            // Snapshots are compared along Git history and reviewed per commit.
            logger.warn("Tuist: Snapshots are uploaded per Git commit, and $root has none; nothing uploaded.")
            return
        }
        val uploader = SnapshotUploader(httpClient, httpClients.okHttp)
        val build = uploader.upload(setName.get(), images, git, diffThreshold.orNull, allImageNames)
        logger.lifecycle("Tuist: Uploaded ${images.size} snapshot images (${build.uploaded} new) to set '${setName.get()}'.")
        val result = uploader.awaitResult(build.id)
        val summary = listOf(
            "${result.changedCount} changed",
            "${result.addedCount} added",
            "${result.removedCount} removed",
            "${result.renamedCount} renamed",
            "${result.unchangedCount} unchanged",
            "${result.skippedCount} skipped"
        ).joinToString(", ")
        when (result.status) {
            "needs_review" -> {
                val message = "Tuist: Snapshots changed against the baseline ($summary). Review them at ${result.url}"
                if (failOnChanges.get()) throw GradleException(message) else logger.warn(message)
            }
            "rejected" -> {
                val message = "Tuist: A reviewer rejected these snapshot changes ($summary). See ${result.url}"
                if (failOnChanges.get()) throw GradleException(message) else logger.warn(message)
            }
            "failed" -> throw GradleException("Tuist: The snapshot comparison failed. See ${result.url}")
            // Passing without a verdict would let unreviewed changes through.
            "processing" -> throw GradleException(
                "Tuist: The snapshot comparison didn't finish in time, so these snapshots have no verdict. See ${result.url}"
            )
            else -> logger.lifecycle("Tuist: Snapshots ${result.status} ($summary): ${result.url}")
        }
    }
}

internal data class SnapshotImage(
    val name: String,
    val file: File,
    val contentHash: String,
    val width: Int?,
    val height: Int?,
    val metadata: SnapshotMetadata = SnapshotMetadata()
)

/** The JSON file next to an image, in the format Sentry's snapshot uploads use. */
internal data class SnapshotMetadata(
    @SerializedName("display_name") val displayName: String? = null,
    val group: String? = null,
    val tags: Map<String, String>? = null,
    @SerializedName("diff_threshold") val diffThreshold: Double? = null
) {
    companion object {
        private val logger = Logging.getLogger(SnapshotMetadata::class.java)

        fun read(image: File): SnapshotMetadata {
            val file = File(image.parentFile, image.name.removeSuffix(".png") + ".json")
            if (!file.isFile) return SnapshotMetadata()
            return try {
                val json = Gson().fromJson(file.readText(), JsonObject::class.java) ?: return SnapshotMetadata()
                SnapshotMetadata(
                    displayName = json.get("display_name")?.takeIf { it.isJsonPrimitive }?.asString,
                    group = json.get("group")?.takeIf { it.isJsonPrimitive }?.asString,
                    // Sentry accepts tags as an object or a list; values become strings either way.
                    tags = json.get("tags")?.let { tags ->
                        when {
                            tags.isJsonObject -> tags.asJsonObject.entrySet()
                                .associate { (key, value) -> key to if (value.isJsonPrimitive) value.asString else value.toString() }
                            tags.isJsonArray -> tags.asJsonArray.filter { it.isJsonPrimitive }.associate { it.asString to "true" }
                            else -> null
                        }
                    },
                    diffThreshold = json.get("diff_threshold")?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isNumber }?.asDouble
                )
            } catch (e: Exception) {
                logger.warn("Tuist: Ignoring the snapshot metadata in ${file.name}: ${e.message}")
                SnapshotMetadata()
            }
        }
    }
}

internal object SnapshotImages {
    /**
     * Lists every image the suite renders, one name per line, so a run filtered to some tests
     * reports the others as skipped rather than removed (Sentry's `--all-image-file-names`).
     * The generated preview test writes it; any other recorder may too.
     */
    const val ALL_IMAGE_NAMES_FILE = "tuist-all-image-names.txt"

    fun allImageNames(directory: File): List<String>? =
        File(directory, ALL_IMAGE_NAMES_FILE).takeIf { it.isFile }
            ?.readLines()?.map { it.trim() }?.filter { it.isNotEmpty() }?.distinct()

    /** Roborazzi's compare and verify tasks write these next to the recorded images. */
    private val derivedSuffixes = listOf("_compare.png", "_actual.png", "_diff.png")

    fun collect(directory: File): List<SnapshotImage> {
        if (!directory.isDirectory) return emptyList()
        return directory.walkTopDown()
            .filter { it.isFile && it.name.endsWith(".png") && derivedSuffixes.none(it.name::endsWith) }
            .map { file ->
                val (width, height) = pngDimensions(file) ?: (null to null)
                SnapshotImage(
                    name = file.relativeTo(directory).invariantSeparatorsPath,
                    file = file,
                    contentHash = sha256(file),
                    width = width,
                    height = height,
                    metadata = SnapshotMetadata.read(file)
                )
            }
            .sortedBy { it.name }
            .toList()
    }

    /** The width and height from a PNG's IHDR chunk, which always comes first. */
    internal fun pngDimensions(file: File): Pair<Int, Int>? = try {
        DataInputStream(file.inputStream().buffered()).use { input ->
            val header = ByteArray(16)
            input.readFully(header)
            val signature = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
            if (!header.copyOfRange(0, 8).contentEquals(signature) || String(header, 12, 4, Charsets.US_ASCII) != "IHDR") null
            else input.readInt() to input.readInt()
        }
    } catch (e: IOException) {
        null
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

/** What a snapshot build reports about its commit, so the server can choose its baseline. */
internal data class SnapshotGitContext(
    val commitSha: String?,
    val branch: String?,
    val ref: String?,
    val remoteUrlOrigin: String?,
    val mergeBaseSha: String?,
    val pullRequestNumber: Int?,
    val pullRequestTitle: String? = null,
    val isCi: Boolean
) {
    companion object {
        private val logger = Logging.getLogger(SnapshotGitContext::class.java)

        /**
         * Reads the checkout and, on CI, collects and uploads its history the way test insights
         * does: the merge base with the base branch, and the commits the server's graph lacks, so
         * the server can walk to the nearest baseline. Best effort: without it the server falls
         * back to the default branch's latest build.
         */
        fun read(root: File, httpClient: TuistHttpClient, serverUrl: String): SnapshotGitContext {
            val runner = ProcessGitRunner(root)
            val gitInfo = ProcessGitInfoProvider(gitCommandRunner = { args -> runner.capture(args).trim().lineSequence().first() })
            val isCi = EnvironmentCIDetector().isCi()
            val history = try {
                val service = GitHistoryService(httpClient = httpClient, baseUrl = serverUrl)
                service.collect(gitInfo, root, isCi)?.also { service.upload(it) }
            } catch (e: Exception) {
                logger.info("Tuist: The snapshot build's Git history could not be collected: ${e.message}")
                null
            }
            return SnapshotGitContext(
                commitSha = gitInfo.commitSha(),
                branch = gitInfo.branch(),
                ref = gitInfo.ref(),
                remoteUrlOrigin = gitInfo.remoteUrlOrigin(),
                mergeBaseSha = history?.payload?.mergeBaseSha,
                pullRequestNumber = history?.payload?.pullRequestNumber,
                pullRequestTitle = pullRequestTitle(System::getenv),
                isCi = isCi
            )
        }

        /**
         * The pull request's title, which only CI knows: GitHub Actions has it in the event
         * payload, and GitLab in `CI_MERGE_REQUEST_TITLE`.
         */
        internal fun pullRequestTitle(environment: (String) -> String?): String? {
            environment("CI_MERGE_REQUEST_TITLE")?.takeIf { it.isNotBlank() }?.let { return it.take(1024) }
            val event = environment("GITHUB_EVENT_PATH")?.let(::File)?.takeIf { it.isFile } ?: return null
            return try {
                Gson().fromJson(event.readText(), JsonObject::class.java)
                    ?.getAsJsonObject("pull_request")?.get("title")
                    ?.takeIf { it.isJsonPrimitive }?.asString?.takeIf { it.isNotBlank() }?.take(1024)
            } catch (e: Exception) {
                logger.info("Tuist: The pull request title could not be read: ${e.message}")
                null
            }
        }
    }
}

internal data class SnapshotBuildResult(
    val id: String,
    val url: String,
    val state: String,
    val status: String,
    @SerializedName("changed_count") val changedCount: Int = 0,
    @SerializedName("added_count") val addedCount: Int = 0,
    @SerializedName("removed_count") val removedCount: Int = 0,
    @SerializedName("renamed_count") val renamedCount: Int = 0,
    @SerializedName("skipped_count") val skippedCount: Int = 0,
    @SerializedName("unchanged_count") val unchangedCount: Int = 0
)

internal class SnapshotUploader(
    private val httpClient: TuistHttpClient,
    okHttp: OkHttpClient,
    private val sleeper: (Long) -> Unit = Thread::sleep,
    private val pollIntervalMs: Long = 2_000,
    private val timeoutMs: Long = 10 * 60_000
) {
    // Redirects and OkHttp's own replays are off: the retry policy decides what may be resent.
    private val client = okHttp.newBuilder().followRedirects(false).retryOnConnectionFailure(false).build()
    private val gson = Gson()
    private val json = "application/json".toMediaType()

    data class CreatedBuild(val id: String, val uploaded: Int)

    fun upload(
        set: String,
        images: List<SnapshotImage>,
        git: SnapshotGitContext,
        diffThreshold: Double? = null,
        allImageNames: List<String>? = null
    ): CreatedBuild {
        val body = mapOf(
            "set" to set,
            "build_system" to "gradle",
            "git_commit_sha" to git.commitSha,
            "git_branch" to git.branch,
            "git_ref" to git.ref,
            "git_remote_url_origin" to git.remoteUrlOrigin,
            "merge_base_sha" to git.mergeBaseSha,
            "pull_request_number" to git.pullRequestNumber,
            "pull_request_title" to git.pullRequestTitle,
            "all_image_names" to allImageNames,
            "is_ci" to git.isCi,
            "images" to images.map {
                mapOf(
                    "name" to it.name,
                    "content_hash" to it.contentHash,
                    "width" to it.width,
                    "height" to it.height,
                    "display_name" to it.metadata.displayName,
                    "group" to it.metadata.group,
                    "tags" to it.metadata.tags?.takeIf { tags -> tags.isNotEmpty() },
                    "diff_threshold" to (it.metadata.diffThreshold ?: diffThreshold)
                ).filterValues { value -> value != null }
            }
        ).filterValues { it != null }
        // Creating a build is not replay-safe: a resent request after a lost response creates another build.
        val response = request("POST", "", body, replaySafe = false)
        val buildId = response.getAsJsonObject("build").get("id").asString
        val byHash = images.groupBy { it.contentHash }
        val uploads = response.getAsJsonArray("uploads")
        uploads.forEach { element ->
            val upload = element.asJsonObject
            val file = byHash.getValue(upload.get("content_hash").asString).first().file
            // Content-addressed: putting the same bytes again changes nothing.
            httpClient.retrying("snapshot image upload", replaySafe = true) {
                val request = Request.Builder().url(upload.get("url").asString)
                    .put(file.asRequestBody("image/png".toMediaType())).build()
                client.newCall(request).execute().use { result ->
                    if (!result.isSuccessful) throw TuistRetry.statusFailure(result.code, result.header("Retry-After")) {
                        IOException("Uploading a snapshot image failed with HTTP ${result.code}")
                    }
                }
            }
        }
        request("POST", "/$buildId/complete", null, replaySafe = true)
        return CreatedBuild(buildId, uploads.size())
    }

    fun awaitResult(buildId: String): SnapshotBuildResult {
        var waited = 0L
        while (true) {
            val result = gson.fromJson(request("GET", "/$buildId", null, replaySafe = true), SnapshotBuildResult::class.java)
            if (result.status != "processing" || waited >= timeoutMs) return result
            sleeper(pollIntervalMs)
            waited += pollIntervalMs
        }
    }

    private fun request(method: String, path: String, body: Any?, replaySafe: Boolean): JsonObject =
        httpClient.execute { config ->
            val url = URI(config.url.trimEnd('/') + "/api/projects/${config.accountHandle}/${config.projectHandle}/snapshots/builds$path")
            httpClient.retrying("snapshot build request", replaySafe = replaySafe) {
                val requestBody = when {
                    body != null -> gson.toJson(body).toRequestBody(json)
                    method == "POST" -> "".toRequestBody(json)
                    else -> null
                }
                val request = Request.Builder().url(url.toURL())
                    .header("Authorization", "Bearer ${config.token}")
                    .header("Accept", "application/json")
                    .method(method, requestBody)
                    .build()
                client.newCall(request).execute().use { response ->
                    val text = response.body?.string().orEmpty()
                    when {
                        response.code == 401 -> throw TokenExpiredException()
                        response.isSuccessful -> gson.fromJson(text, JsonObject::class.java)
                        response.code in 400..499 -> throw GradleException(
                            "Tuist: The snapshot build request failed (HTTP ${response.code}): " +
                                (runCatching { gson.fromJson(text, JsonObject::class.java).get("message").asString }.getOrNull() ?: text)
                        )
                        else -> throw TuistRetry.statusFailure(response.code, response.header("Retry-After")) {
                            IOException("The snapshot build request failed with HTTP ${response.code}")
                        }
                    }
                }
            }
        }
}
