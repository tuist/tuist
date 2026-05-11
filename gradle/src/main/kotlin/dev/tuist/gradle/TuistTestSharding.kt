package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.ShardsApi
import dev.tuist.gradle.api.model.CreateShardPlanParams1
import dev.tuist.gradle.api.model.Shard
import dev.tuist.gradle.api.model.ShardPlan
import okhttp3.OkHttpClient
import org.gradle.api.DefaultTask
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.logging.Logging
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.IgnoreEmptyDirectories
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.SkipWhenEmpty
import org.gradle.api.tasks.TaskAction
import org.gradle.api.tasks.testing.Test
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

class TuistTestShardingService(
    private val shardsApi: ShardsApi,
    private val accountHandle: String,
    private val projectHandle: String
) {
    private val logger = Logging.getLogger(TuistTestShardingService::class.java)

    constructor(
        baseUrl: String,
        token: String,
        accountHandle: String,
        projectHandle: String,
        httpClients: TuistHttpClients = TuistHttpClients()
    ) : this(
        shardsApi = createShardsApi(baseUrl, token, httpClients),
        accountHandle = accountHandle,
        projectHandle = projectHandle
    )

    fun createShardPlan(
        reference: String,
        testSuites: List<String>,
        shardMax: Int,
        shardMin: Int?,
        shardMaxDuration: Int?,
        gradleBuildId: String? = null
    ): ShardPlan {
        val body = CreateShardPlanParams1(
            reference = reference,
            testSuites = testSuites,
            shardMin = shardMin,
            shardMax = shardMax,
            shardMaxDuration = shardMaxDuration,
            granularity = CreateShardPlanParams1.Granularity.suite,
            gradleBuildId = gradleBuildId
        )

        val response = shardsApi.createShardPlan(accountHandle, projectHandle, body).execute()
        if (!response.isSuccessful) {
            throw org.gradle.api.GradleException("Shard plan creation failed with HTTP ${response.code()}: ${response.errorBody()?.string() ?: "(no response body)"}")
        }
        return response.body() ?: throw org.gradle.api.GradleException("Shard plan creation returned empty response.")
    }

    fun getShard(reference: String, shardIndex: Int): Shard {
        val response = shardsApi.getShard(accountHandle, projectHandle, reference, shardIndex).execute()
        if (!response.isSuccessful) {
            throw org.gradle.api.GradleException("Get shard failed with HTTP ${response.code()}: ${response.errorBody()?.string() ?: "(no response body)"}")
        }
        return response.body() ?: throw org.gradle.api.GradleException("Get shard returned empty response.")
    }

    fun deriveReference(): String? {
        System.getenv("GITHUB_RUN_ID")?.let { runId ->
            val attempt = System.getenv("GITHUB_RUN_ATTEMPT") ?: "1"
            return "github-$runId-$attempt"
        }
        System.getenv("CIRCLE_WORKFLOW_ID")?.let { return "circleci-$it" }
        System.getenv("BUILDKITE_BUILD_ID")?.let { return "buildkite-$it" }
        System.getenv("CI_PIPELINE_ID")?.let { return "gitlab-$it" }
        System.getenv("CM_BUILD_ID")?.let { return "codemagic-$it" }
        return null
    }
}

private fun createShardsApi(
    baseUrl: String,
    token: String,
    httpClients: TuistHttpClients = TuistHttpClients()
): ShardsApi {
    // Branch a short-timeout variant off the shared OkHttp client so the
    // proxy (and connection pool) from [httpClients] is reused.
    val client = httpClients.okHttp.newBuilder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            val request = chain.request().newBuilder()
                .header("Authorization", "Bearer $token")
                .build()
            chain.proceed(request)
        }
        .build()

    return Retrofit.Builder()
        .baseUrl(baseUrl.trimEnd('/') + "/")
        .client(client)
        .addConverterFactory(GsonConverterFactory.create())
        .build()
        .create(ShardsApi::class.java)
}

fun discoverTestSuitesFromDirs(classDirs: List<java.io.File>): List<String> {
    val testSuites = mutableSetOf<String>()
    for (dir in classDirs) {
        if (!dir.exists()) continue
        dir.walkTopDown()
            .filter { it.isFile && it.extension == "class" && !it.name.contains('$') }
            .forEach { file ->
                val fqcn = file.relativeTo(dir).path
                    .removeSuffix(".class")
                    .replace(java.io.File.separatorChar, '.')
                testSuites.add(fqcn)
            }
    }
    return testSuites.sorted()
}

abstract class TuistPrepareTestShardsTask : DefaultTask() {

    private enum class CIProvider {
        GITHUB, GITLAB, CIRCLECI, BUILDKITE, CODEMAGIC, BITRISE
    }

    private fun detectCIProvider(env: EnvironmentProvider): CIProvider? {
        if (env.getenv("GITHUB_ACTIONS") != null) return CIProvider.GITHUB
        if (env.getenv("GITLAB_CI") != null) return CIProvider.GITLAB
        if (env.getenv("CIRCLECI") != null) return CIProvider.CIRCLECI
        if (env.getenv("BUILDKITE") != null) return CIProvider.BUILDKITE
        if (env.getenv("CM_BUILD_ID") != null) return CIProvider.CODEMAGIC
        if (env.getenv("BITRISE_IO") != null) return CIProvider.BITRISE
        return null
    }

    /** Maximum number of shards to distribute tests across. */
    @get:Input
    var shardMax: Int = 2

    /** Minimum number of shards. */
    @get:Input
    @get:Optional
    var shardMin: Int? = null

    /** Target maximum duration per shard in milliseconds. */
    @get:Input
    @get:Optional
    var shardMaxDuration: Int? = null

    /** Explicit shard reference. Derived from CI environment variables when not set. */
    @get:Input
    @get:Optional
    var shardReference: String? = null

    @get:Internal
    var serverUrl: String = "https://tuist.dev"

    @get:Internal
    var tuistProject: String? = null

    @get:Input
    var useEnvironmentProxy: Boolean = true

    @get:InputFiles
    @get:SkipWhenEmpty
    @get:IgnoreEmptyDirectories
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val compiledTestClassDirectories: ConfigurableFileCollection

    @TaskAction
    fun execute() {
        val shardingService = createShardingService()

        val reference = shardReference
            ?: shardingService.deriveReference()
            ?: throw org.gradle.api.GradleException(
                "Could not derive shard reference. Set TUIST_SHARD_REFERENCE or run in a supported CI environment."
            )

        val testSuites = discoverTestSuitesFromDirs(compiledTestClassDirectories.files.toList())
        if (testSuites.isEmpty()) {
            throw org.gradle.api.GradleException("No test classes found in compiled test output.")
        }

        logger.lifecycle("Tuist: Discovered ${testSuites.size} test suite(s): ${testSuites.joinToString(", ")}")

        val gradleBuildId = project.gradle.sharedServices.registrations
            .findByName("tuistBuildInsights")?.service?.orNull
            ?.let { (it as? TuistBuildInsightsService)?.buildId }

        val response = shardingService.createShardPlan(
            reference = reference,
            testSuites = testSuites,
            shardMax = shardMax,
            shardMin = shardMin,
            shardMaxDuration = shardMaxDuration,
            gradleBuildId = gradleBuildId
        )

        logger.lifecycle("Tuist: Shard plan created — reference=$reference, shards=${response.shardCount}")
        for (shard in response.shards) {
            logger.lifecycle("Tuist:   Shard ${shard.index}: ${shard.testTargets.joinToString(", ")} (est. ${shard.estimatedDurationMs}ms)")
        }

        val indices = (0 until response.shardCount).toList()
        writeShardMatrixOutput(indices, reference, response)
    }

    fun writeShardMatrixOutput(
        indices: List<Int>,
        reference: String,
        response: ShardPlan,
        env: EnvironmentProvider = SystemEnvironmentProvider()
    ) {
        when (detectCIProvider(env)) {
            CIProvider.GITHUB -> {
                val matrixJSON = """{"shard":$indices}"""
                java.io.File(env.getenv("GITHUB_OUTPUT")!!).appendText("matrix=$matrixJSON\n")
                logger.lifecycle("Tuist: GitHub Actions matrix output written.")
            }
            CIProvider.GITLAB -> {
                val yaml = buildString {
                    for (index in indices) {
                        appendLine("shard-$index:")
                        appendLine("  extends: .tuist-shard")
                        appendLine("  variables:")
                        appendLine("    TUIST_SHARD_INDEX: \"$index\"")
                        appendLine()
                    }
                }
                val outputFile = project.projectDir.resolve(".tuist-shard-child-pipeline.yml")
                outputFile.writeText(yaml)
                logger.lifecycle("Tuist: GitLab CI child pipeline written to ${outputFile.path}")
            }
            CIProvider.CIRCLECI -> {
                val parameters = mapOf(
                    "shard-indices" to indices.joinToString(","),
                    "shard-count" to indices.size
                )
                val outputFile = project.projectDir.resolve(".tuist-shard-continuation.json")
                outputFile.writeText(Gson().toJson(parameters))
                logger.lifecycle("Tuist: CircleCI continuation parameters written to ${outputFile.path}")
            }
            CIProvider.BUILDKITE -> {
                val yaml = buildString {
                    appendLine("steps:")
                    for (index in indices) {
                        appendLine("  - label: \"Shard #$index\"")
                        appendLine("    env:")
                        appendLine("      TUIST_SHARD_INDEX: \"$index\"")
                        appendLine()
                    }
                }
                val outputFile = project.projectDir.resolve(".tuist-shard-pipeline.yml")
                outputFile.writeText(yaml)
                logger.lifecycle("Tuist: Buildkite pipeline written to ${outputFile.path}")
            }
            CIProvider.CODEMAGIC -> {
                val matrixJSON = """{"shard":$indices}"""
                java.io.File(env.getenv("CM_ENV")!!).appendText("TUIST_SHARD_MATRIX=$matrixJSON\nTUIST_SHARD_COUNT=${indices.size}\n")
                logger.lifecycle("Tuist: Codemagic environment variables written to CM_ENV.")
            }
            CIProvider.BITRISE -> {
                val matrixJSON = """{"shard":$indices,"shard_count":${indices.size}}"""
                val deployDir = env.getenv("BITRISE_DEPLOY_DIR")!!
                java.io.File(deployDir, ".tuist-shard-matrix.json").writeText(matrixJSON)
                logger.lifecycle("Tuist: Bitrise shard matrix written to deploy directory.")
            }
            null -> {
                val matrix = mapOf(
                    "reference" to reference,
                    "shard_count" to response.shardCount,
                    "shards" to response.shards.map { shard ->
                        mapOf(
                            "index" to shard.index,
                            "test_targets" to shard.testTargets,
                            "estimated_duration_ms" to shard.estimatedDurationMs
                        )
                    }
                )
                val outputFile = project.projectDir.resolve(".tuist-shard-matrix.json")
                outputFile.writeText(Gson().toJson(matrix))
                logger.lifecycle("Tuist: Shard matrix written to ${outputFile.path}")
            }
        }
    }

    private fun createShardingService(): TuistTestShardingService {
        val httpClients = TuistHttpClients(useEnvironmentProxy = useEnvironmentProxy)
        val configProvider = DefaultConfigurationProvider(
            project = tuistProject,
            serverUrl = serverUrl,
            projectDir = project.rootDir,
            httpClients = httpClients
        )
        val config = configProvider.getConfiguration()
        return TuistTestShardingService(
            baseUrl = serverUrl,
            token = config.token,
            accountHandle = config.accountHandle,
            projectHandle = config.projectHandle,
            httpClients = httpClients
        )
    }
}

abstract class TuistTestShardingPlugin : Plugin<Project> {

    private val logger = Logging.getLogger(TuistTestShardingPlugin::class.java)

    override fun apply(project: Project) {
        // Only apply the sharding plugin to the root project to avoid duplicate task registration
        // and filter configuration when the plugin is applied transitively to subprojects.
        if (project !== project.rootProject) return

        val config = TuistGradleConfig.from(project) ?: return
        val providers = project.providers
        val testClassDirectories = project.objects.fileCollection()

        val prepareTestShards = project.tasks.register("tuistPrepareTestShards", TuistPrepareTestShardsTask::class.java)
        prepareTestShards.configure {
            group = "tuist"
            description = "Build test classes, discover test suites, and create a shard plan on the Tuist server"
            serverUrl = config.url
            tuistProject = config.project
            useEnvironmentProxy = config.network.proxy
            compiledTestClassDirectories.from(testClassDirectories)

            providers.gradleProperty("tuistShardMax").orNull?.toIntOrNull()?.let { shardMax = it }
            providers.gradleProperty("tuistShardMin").orNull?.toIntOrNull()?.let { shardMin = it }
            providers.gradleProperty("tuistShardMaxDuration").orNull?.toIntOrNull()?.let { shardMaxDuration = it }
            providers.environmentVariable("TUIST_SHARD_REFERENCE").orNull?.let { shardReference = it }
        }

        project.allprojects.forEach { subproject ->
            subproject.tasks.withType(Test::class.java).configureEach {
                testClassDirectories.from(testClassesDirs)
            }
        }

        val shardIndexStr = providers.environmentVariable("TUIST_SHARD_INDEX").orNull ?: return
        val shardIndex = shardIndexStr.toIntOrNull()
        if (shardIndex == null) {
            logger.warn("Tuist: TUIST_SHARD_INDEX is not a valid integer: $shardIndexStr")
            return
        }

        val httpClients = TuistHttpClients(useEnvironmentProxy = config.network.proxy)
        val configProvider = DefaultConfigurationProvider(
            project = config.project,
            serverUrl = config.url,
            projectDir = project.rootProject.projectDir,
            httpClients = httpClients
        )
        val cacheConfig = configProvider.getConfiguration()
        val shardingService = TuistTestShardingService(
            baseUrl = config.url,
            token = cacheConfig.token,
            accountHandle = cacheConfig.accountHandle,
            projectHandle = cacheConfig.projectHandle,
            httpClients = httpClients
        )

        val reference = providers.environmentVariable("TUIST_SHARD_REFERENCE").orNull ?: shardingService.deriveReference()
            ?: throw org.gradle.api.GradleException(
                "Could not derive shard reference. Set TUIST_SHARD_REFERENCE or run in a supported CI environment."
            )

        logger.lifecycle("Tuist: Test sharding active — shard index $shardIndex, reference $reference")

        val shard = shardingService.getShard(reference, shardIndex)

        val assignedTargets = shard.suites.values.flatten()
        logger.lifecycle("Tuist: Shard $shardIndex assigned ${assignedTargets.size} test suite(s)")

        // Set shard context on the test insights service so it's included in the test report
        project.gradle.sharedServices.registrations.findByName("tuistTestInsights")?.let { registration ->
            val service = registration.service.orNull
            if (service is TuistTestInsightsService) {
                service.shardPlanId = shard.shardPlanId.toString()
                service.shardIndex = shardIndex
            }
        }

        project.allprojects {
            val subproject = this
            subproject.tasks.withType(Test::class.java).configureEach {
                val testTask = this
                testTask.doFirst {
                    testTask.filter.isFailOnNoMatchingTests = false
                    for (target in assignedTargets) {
                        testTask.filter.includeTestsMatching(target)
                    }
                    logger.lifecycle("Tuist: Applied shard filter to test task '${testTask.path}' with ${assignedTargets.size} suite(s)")
                }
            }
        }
    }
}
