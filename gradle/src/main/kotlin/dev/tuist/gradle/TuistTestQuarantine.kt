package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.logging.Logging
import org.gradle.api.provider.Property
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URI

data class QuarantinedTestCasesResponse(
    @SerializedName("test_cases") val testCases: List<QuarantinedTestCase>
)

data class QuarantinedTestCase(
    val name: String,
    val module: QuarantinedModule,
    val suite: QuarantinedSuite?
)

data class QuarantinedModule(
    val id: String,
    val name: String
)

data class QuarantinedSuite(
    val id: String,
    val name: String
)

data class TestIdentifier(
    val suiteName: String?,
    val testName: String
) {
    fun matches(className: String?, name: String): Boolean {
        if (suiteName != null && suiteName != className) return false
        return testName == name
    }
}

class TuistTestQuarantineService(
    private val httpClient: TuistHttpClient,
    private val baseUrl: String
) {
    private val logger = Logging.getLogger(TuistTestQuarantineService::class.java)

    private var cachedExclusions: Map<String, List<TestIdentifier>>? = null

    @Synchronized
    fun getQuarantinedTests(): Map<String, List<TestIdentifier>> {
        cachedExclusions?.let { return it }

        val result = try {
            fetchQuarantinedTests()
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to fetch quarantined tests: ${e.message}")
            emptyMap()
        }

        cachedExclusions = result
        return result
    }

    private fun fetchQuarantinedTests(): Map<String, List<TestIdentifier>> {
        return httpClient.execute { config ->
            val url = URI(baseUrl.trimEnd('/')).resolve(
                "/api/projects/${config.accountHandle}/${config.projectHandle}/tests/test-cases?quarantined=true&page_size=500"
            )
            val connection = httpClient.openConnection(url, config)
            try {
                connection.requestMethod = "GET"
                connection.setRequestProperty("Accept", "application/json")

                when (connection.responseCode) {
                    HttpURLConnection.HTTP_OK -> {
                        val response = BufferedReader(
                            InputStreamReader(connection.inputStream, Charsets.UTF_8)
                        ).use { reader ->
                            Gson().fromJson(reader, QuarantinedTestCasesResponse::class.java)
                        }
                        buildQuarantineMap(response.testCases)
                    }
                    HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                    else -> {
                        val errorBody = try {
                            connection.errorStream?.bufferedReader()?.use { it.readText() }
                        } catch (_: Exception) { null }
                        logger.warn(
                            "Tuist: Quarantine request failed with HTTP ${connection.responseCode}: ${errorBody ?: "(no response body)"}"
                        )
                        emptyMap()
                    }
                }
            } finally {
                connection.disconnect()
            }
        }
    }

    private fun buildQuarantineMap(testCases: List<QuarantinedTestCase>): Map<String, List<TestIdentifier>> {
        return testCases.groupBy(
            keySelector = { it.module.name },
            valueTransform = { testCase ->
                TestIdentifier(
                    suiteName = testCase.suite?.name?.takeIf { it.isNotBlank() },
                    testName = testCase.name
                )
            }
        )
    }
}

/**
 * Gradle [BuildService] wrapper around [TuistTestQuarantineService].
 *
 * The HTTP plumbing (OkHttp clients, configuration provider, token provider) is
 * built lazily inside the service rather than captured in task action closures.
 * This keeps the configuration cache happy: only serializable parameters
 * (server URL, project handle, working directory) are written to disk — the
 * non-serializable OkHttp machinery is rebuilt on demand at execution time.
 */
abstract class TuistTestQuarantineBuildService :
    BuildService<TuistTestQuarantineBuildService.Params> {

    interface Params : BuildServiceParameters {
        val serverUrl: Property<String>
        val tuistProject: Property<String>
        val useEnvironmentProxy: Property<Boolean>
        val projectDir: DirectoryProperty
    }

    @Volatile
    private var delegate: TuistTestQuarantineService? = null
    private val lock = Any()

    fun getQuarantinedTests(): Map<String, List<TestIdentifier>> = resolveDelegate().getQuarantinedTests()

    private fun resolveDelegate(): TuistTestQuarantineService {
        delegate?.let { return it }
        return synchronized(lock) {
            delegate ?: createDelegate().also { delegate = it }
        }
    }

    private fun createDelegate(): TuistTestQuarantineService {
        val serverUrl = parameters.serverUrl.get()
        val httpClients = TuistHttpClients(useEnvironmentProxy = parameters.useEnvironmentProxy.get())
        val configProvider = DefaultConfigurationProvider(
            project = parameters.tuistProject.orNull,
            serverUrl = serverUrl,
            projectDir = parameters.projectDir.asFile.get(),
            httpClients = httpClients
        )
        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            httpClients = httpClients,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )
        return TuistTestQuarantineService(httpClient = httpClient, baseUrl = serverUrl)
    }
}
