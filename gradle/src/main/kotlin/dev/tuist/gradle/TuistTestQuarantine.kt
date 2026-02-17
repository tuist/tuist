package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.logging.Logging
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

class TuistTestQuarantineService(
    private val httpClient: TuistHttpClient,
    private val baseUrl: String
) {
    private val logger = Logging.getLogger(TuistTestQuarantineService::class.java)

    private var cachedExclusions: Map<String, List<String>>? = null

    @Synchronized
    fun getQuarantinedTests(): Map<String, List<String>> {
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

    private fun fetchQuarantinedTests(): Map<String, List<String>> {
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
                        buildExclusionMap(response.testCases)
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

    private fun buildExclusionMap(testCases: List<QuarantinedTestCase>): Map<String, List<String>> {
        return testCases.groupBy(
            keySelector = { it.module.name },
            valueTransform = { testCase ->
                val suiteName = testCase.suite?.name?.takeIf { it.isNotBlank() }
                if (suiteName != null) {
                    "$suiteName.${testCase.name}"
                } else {
                    "*.${testCase.name}"
                }
            }
        )
    }
}
