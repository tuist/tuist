package dev.tuist.gradle

import org.gradle.internal.cc.impl.InputTrackingState
import java.lang.management.ManagementFactory
import java.net.HttpURLConnection
import java.net.URI
import java.nio.charset.Charset
import java.util.Locale

internal const val EXPANDED_BUILD_METADATA_VALUES = 64

/** Optional observations of the reporting build process, never the target platform. */
internal fun buildEnvironmentMetadata(
    properties: (String) -> String? = System::getProperty,
    environment: Map<String, String> = System.getenv(),
    processors: () -> Int = { Runtime.getRuntime().availableProcessors() },
    memory: () -> Long? = {
        (ManagementFactory.getOperatingSystemMXBean() as? com.sun.management.OperatingSystemMXBean)?.totalMemorySize
    },
    heap: () -> Long = { Runtime.getRuntime().maxMemory() },
    locale: () -> String = { Locale.getDefault().toLanguageTag() },
    charset: () -> String = { Charset.defaultCharset().name() },
    maxWorkers: Int? = null
): Map<String, String> = buildMap {
    fun observe(key: String, probe: () -> Any?) {
        try {
            val value = probe()?.toString() ?: return
            if (value.isNotBlank() && value.length <= MAX_BUILD_METADATA_VALUE_LENGTH) put(key, value)
        } catch (_: Exception) {
            // Telemetry must not make an otherwise valid build fail.
        } catch (_: LinkageError) {
            // OS management interfaces differ between supported JVMs.
        }
    }
    observe("tuist.os.type") {
        when (properties("os.name")?.lowercase(Locale.ROOT)) {
            "linux" -> "linux"
            "mac os x", "darwin" -> "darwin"
            null -> null
            else -> properties("os.name")?.let { if (it.startsWith("Windows")) "windows" else it }
        }
    }
    observe(if (get("tuist.os.type") == "linux") "tuist.os.kernel_version" else "tuist.os.version") {
        properties("os.version")
    }
    observe("tuist.host.arch") { properties("os.arch") }
    observe("tuist.cpu.available_processors") { processors().takeIf { it > 0 } }
    observe("tuist.memory.total_bytes") { memory()?.takeIf { it > 0 } }
    observe("tuist.process.locale", locale)
    observe("tuist.process.charset", charset)
    observe("tuist.jvm.vendor") { properties("java.vendor") }
    observe("tuist.jvm.runtime_name") { properties("java.runtime.name") }
    observe("tuist.jvm.runtime_version") { properties("java.runtime.version") }
    observe("tuist.jvm.vm_name") { properties("java.vm.name") }
    observe("tuist.jvm.vm_version") { properties("java.vm.version") }
    observe("tuist.jvm.max_heap_bytes") { heap().takeIf { it > 0 } }
    observe("tuist.gradle.max_workers") { maxWorkers?.takeIf { it > 0 } }
    val provider = when {
        environment["GITHUB_ACTIONS"] == "true" -> "github"
        environment["GITLAB_CI"] == "true" -> "gitlab"
        environment["BUILDKITE"] == "true" -> "buildkite"
        environment["CIRCLECI"] == "true" -> "circleci"
        environment["BITRISE_IO"] == "true" -> "bitrise"
        else -> null
    }
    observe("tuist.ci.provider") { provider }
    observe("tuist.ci.job") {
        when (provider) {
            "github" -> environment["GITHUB_JOB"]
            "gitlab" -> environment["CI_JOB_NAME"]
            "buildkite" -> environment["BUILDKITE_LABEL"]
            else -> null
        }
    }
    observe("tuist.ci.runner_environment") { environment["RUNNER_ENVIRONMENT"] }
    if (environment["TUIST_BUILD_METADATA_RUNNER_NAME"] == "1") {
        observe("tuist.ci.runner_name") {
            when (provider) {
                "github" -> environment["RUNNER_NAME"]
                "gitlab" -> environment["CI_RUNNER_DESCRIPTION"]
                "buildkite" -> environment["BUILDKITE_AGENT_NAME"]
                else -> null
            }
        }
    }
}

internal fun BuildCustomMetadata.withObservations(
    observations: Map<String, String>,
    limit: Int = MAX_BUILD_METADATA_VALUES
): BuildCustomMetadata {
    val values = this.values.toMutableMap()
    for ((key, value) in observations) {
        if (values.size >= limit) break
        if (key.length <= MAX_BUILD_METADATA_KEY_LENGTH && value.length <= MAX_BUILD_METADATA_VALUE_LENGTH) {
            values.putIfAbsent(key, value)
        }
    }
    return copy(values = values)
}

/** No credentials, Git context, redirects, retries, or destination-based capability assumptions. */
internal fun discoverBuildMetadataLimit(serverUrl: URI, open: (URI) -> HttpURLConnection): Int {
    var connection: HttpURLConnection? = null
    return try {
        val discoveryUrl = URI(serverUrl.scheme, null, serverUrl.host, serverUrl.port, "/api/metadata/limits", null, null)
        connection = open(discoveryUrl)
        connection.instanceFollowRedirects = false
        connection.requestMethod = "GET"
        connection.connectTimeout = 2_000
        connection.readTimeout = 2_000
        if (connection.responseCode != 200) return MAX_BUILD_METADATA_VALUES
        connection.getHeaderField("x-tuist-custom-metadata-max-values")?.toIntOrNull()
            ?.takeIf { it in MAX_BUILD_METADATA_VALUES..EXPANDED_BUILD_METADATA_VALUES }
            ?: MAX_BUILD_METADATA_VALUES
    } catch (_: Exception) {
        MAX_BUILD_METADATA_VALUES
    } finally {
        connection?.disconnect()
    }
}

internal fun <T> withoutMetadataInputTracking(state: InputTrackingState?, action: () -> T): T {
    state?.disableForCurrentThread()
    return try { action() } finally { state?.restoreForCurrentThread() }
}
