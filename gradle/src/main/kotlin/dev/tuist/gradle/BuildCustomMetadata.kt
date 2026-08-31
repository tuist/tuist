package dev.tuist.gradle

import com.sun.management.OperatingSystemMXBean
import java.io.File
import java.lang.management.ManagementFactory
import java.util.Locale
import java.util.concurrent.TimeUnit

data class BuildCustomMetadata(
    val tags: List<String> = emptyList(),
    val values: Map<String, String> = emptyMap()
)

internal const val MAX_BUILD_METADATA_TAGS = 50
internal const val MAX_BUILD_METADATA_TAG_LENGTH = 50
internal const val MAX_BUILD_METADATA_VALUES = 20
internal const val MAX_BUILD_METADATA_KEY_LENGTH = 50
internal const val MAX_BUILD_METADATA_VALUE_LENGTH = 500

private val validBuildMetadataTag = Regex("^[a-zA-Z0-9_-]+$")

internal interface BuildSystemMetadataProvider {
    fun values(isCi: Boolean): Map<String, String>
}

internal class DefaultBuildSystemMetadataProvider : BuildSystemMetadataProvider {
    override fun values(isCi: Boolean): Map<String, String> = buildMap {
        System.getProperty("os.name")?.takeIf(String::isNotBlank)?.let { put("os_name", it) }
        System.getProperty("os.version")?.takeIf(String::isNotBlank)?.let { put("os_version", it) }
        System.getProperty("os.arch")?.takeIf(String::isNotBlank)?.let { put("os_architecture", it) }
        cpuModel?.let { put("cpu_model", it) }
        put("cpu_cores", Runtime.getRuntime().availableProcessors().toString())
        totalMemoryBytes?.let { put("memory_total_bytes", it.toString()) }
        if (!isCi) powerSource?.let { put("power_source", it) }
    }

    private companion object {
        val cpuModel: String? by lazy(::detectCpuModel)
        val totalMemoryBytes: Long? by lazy(::detectTotalMemoryBytes)
        val powerSource: String? by lazy(::detectPowerSource)

        private fun detectCpuModel(): String? {
            val osName = System.getProperty("os.name").orEmpty().lowercase(Locale.ROOT)

            return when {
                osName.contains("linux") -> linuxCpuModel()
                osName.contains("mac") -> commandOutput("sysctl", "-n", "machdep.cpu.brand_string")
                    ?: commandOutput("sysctl", "-n", "hw.model")
                osName.contains("windows") -> System.getenv("PROCESSOR_IDENTIFIER")
                else -> null
            }
        }

        private fun linuxCpuModel(): String? {
            val cpuInfo = File("/proc/cpuinfo")
            if (!cpuInfo.isFile) return null

            return cpuInfo.useLines { lines -> parseLinuxCpuModel(lines) }
        }

        @Suppress("DEPRECATION")
        private fun detectTotalMemoryBytes(): Long? =
            runCatching {
                (ManagementFactory.getOperatingSystemMXBean() as? OperatingSystemMXBean)
                    ?.totalPhysicalMemorySize
                    ?.takeIf { it > 0 }
            }.getOrNull()

        private fun detectPowerSource(): String? {
            val osName = System.getProperty("os.name").orEmpty().lowercase(Locale.ROOT)

            return when {
                osName.contains("linux") -> linuxPowerSource()
                osName.contains("mac") -> macOsPowerSource()
                else -> null
            }
        }

        private fun linuxPowerSource(): String? {
            val powerSupplyDirectory = File("/sys/class/power_supply")
            val powerSupplies = powerSupplyDirectory.listFiles()?.toList().orEmpty()

            val hasAcPower = powerSupplies.any { supply ->
                supply.readTextOrNull("type") in setOf("Mains", "USB", "USB_C") && supply.readTextOrNull("online") == "1"
            }

            if (hasAcPower) return "ac"

            return if (powerSupplies.any { it.readTextOrNull("type") == "Battery" }) "battery" else null
        }

        private fun macOsPowerSource(): String? =
            commandOutput("pmset", "-g", "batt")?.let { output ->
                when {
                    output.contains("AC Power", ignoreCase = true) -> "ac"
                    output.contains("Battery Power", ignoreCase = true) -> "battery"
                    else -> null
                }
            }

        private fun File.readTextOrNull(name: String): String? =
            try {
                resolve(name).takeIf(File::isFile)?.readText()?.trim()
            } catch (_: Exception) {
                null
            }

        private fun commandOutput(vararg command: String): String? =
            try {
                val process = ProcessBuilder(*command).redirectErrorStream(true).start()

                if (!process.waitFor(2, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                    null
                } else {
                    process.inputStream.bufferedReader().use { it.readText().trim().takeIf(String::isNotEmpty) }
                }
            } catch (_: Exception) {
                null
            }
    }
}

internal fun parseLinuxCpuModel(lines: Sequence<String>): String? {
    val values = mutableMapOf<String, String>()

    lines.forEach { line ->
        val separatorIndex = line.indexOf(':')
        if (separatorIndex == -1) return@forEach

        val key = line.substring(0, separatorIndex).trim().lowercase(Locale.ROOT)
        val value = line.substring(separatorIndex + 1).trim()
        if (value.isNotEmpty()) values.putIfAbsent(key, value)
    }

    return listOf("model name", "hardware", "cpu model")
        .firstNotNullOfOrNull(values::get)
        ?: values["processor"]?.takeUnless { it.all(Char::isDigit) }
}

internal fun commonCustomUserDataMetadata(
    environment: Map<String, String>,
    isCi: Boolean,
    gitInfoProvider: GitInfoProvider,
    systemPropertyProvider: (String) -> String? = System::getProperty
): BuildCustomMetadata {
    val tags = mutableListOf<String>()
    val values = mutableMapOf<String, String>()

    systemPropertyProvider("os.name")
        ?.takeIf(String::isNotBlank)
        ?.let { tags += "os-${tagSegment(it)}" }

    if (isCi) {
        tags += "ci"
        continuousIntegrationMetadata(environment)?.let { metadata ->
            tags += metadata.tag
            values += metadata.values
        }
    } else {
        tags += "local"
        val invocation = invocationMetadata(environment, systemPropertyProvider)
        tags += invocation.tag
        values["invocation_source"] = invocation.name
        invocation.version?.let { values["ide_version"] = it }

        if (!systemPropertyProvider("idea.sync.active").isNullOrBlank()) tags += "ide-sync"
    }

    gitInfoProvider.isDirty()?.let { dirty ->
        if (dirty) tags += "dirty"
        values["git_dirty"] = dirty.toString()
    }

    agentName(environment)?.let { name ->
        tags += "ai"
        values["ai_agent"] = name
    }

    return BuildCustomMetadata(tags = tags, values = values)
}

private data class InvocationMetadata(
    val tag: String,
    val name: String,
    val version: String? = null
)

private fun invocationMetadata(
    environment: Map<String, String>,
    systemPropertyProvider: (String) -> String?
): InvocationMetadata =
    when {
        !systemPropertyProvider("android.injected.invoked.from.ide").isNullOrBlank() ||
            systemPropertyProvider("idea.vendor.name") == "Google" ->
            InvocationMetadata("android-studio", "Android Studio", systemPropertyProvider("idea.version"))

        systemPropertyProvider("idea.vendor.name") == "JetBrains" ->
            InvocationMetadata("intellij-idea", "IntelliJ IDEA", systemPropertyProvider("idea.version"))

        !systemPropertyProvider("eclipse.buildId").isNullOrBlank() ->
            InvocationMetadata("eclipse", "Eclipse", systemPropertyProvider("eclipse.buildId"))

        !environment["VSCODE_PID"].isNullOrBlank() || !environment["VSCODE_INJECTION"].isNullOrBlank() ->
            InvocationMetadata("vs-code", "Visual Studio Code")

        else -> InvocationMetadata("command-line", "Command line")
    }

private data class ContinuousIntegrationMetadata(
    val tag: String,
    val values: Map<String, String>
)

private fun continuousIntegrationMetadata(environment: Map<String, String>): ContinuousIntegrationMetadata? {
    val provider = when {
        !environment["JENKINS_URL"].isNullOrBlank() -> "Jenkins"
        !environment["TEAMCITY_VERSION"].isNullOrBlank() -> "TeamCity"
        environment["CIRCLECI"] == "true" -> "CircleCI"
        !environment["bamboo_buildKey"].isNullOrBlank() -> "Bamboo"
        environment["GITHUB_ACTIONS"] == "true" -> "GitHub Actions"
        environment["GITLAB_CI"] == "true" -> "GitLab"
        environment["TRAVIS"] == "true" -> "Travis CI"
        environment["BITRISE_IO"] == "true" -> "Bitrise"
        !environment["GO_SERVER_URL"].isNullOrBlank() -> "GoCD"
        environment["TF_BUILD"] == "True" || environment["TF_BUILD"] == "true" -> "Azure Pipelines"
        environment["BUILDKITE"] == "true" -> "Buildkite"
        else -> return null
    }

    val values = buildMap {
        put("ci_provider", provider)
        continuousIntegrationBuildUrl(environment)?.let { put("ci_build_url", it) }
        firstEnvironmentValue(
            environment,
            "BUILD_NUMBER",
            "CIRCLE_BUILD_NUM",
            "GITHUB_RUN_NUMBER",
            "CI_JOB_ID",
            "TRAVIS_BUILD_NUMBER",
            "BITRISE_BUILD_NUMBER",
            "BUILDKITE_BUILD_NUMBER"
        )?.let { put("ci_build_number", it) }
        firstEnvironmentValue(
            environment,
            "JOB_NAME",
            "CIRCLE_JOB",
            "GITHUB_JOB",
            "CI_JOB_NAME",
            "TRAVIS_JOB_NAME",
            "BUILDKITE_LABEL"
        )?.let { put("ci_job", it) }
        firstEnvironmentValue(environment, "GITHUB_WORKFLOW", "CI_PIPELINE_NAME", "BUILDKITE_PIPELINE_SLUG")
            ?.let { put("ci_workflow", it) }
        firstEnvironmentValue(environment, "STAGE_NAME", "CI_JOB_STAGE")?.let { put("ci_stage", it) }
        firstEnvironmentValue(environment, "NODE_NAME", "AGENT_NAME", "BUILDKITE_AGENT_NAME")?.let { put("ci_node", it) }
    }

    return ContinuousIntegrationMetadata(tag = "ci-${tagSegment(provider)}", values = values)
}

private fun firstEnvironmentValue(environment: Map<String, String>, vararg keys: String): String? =
    keys.asSequence().mapNotNull(environment::get).firstOrNull(String::isNotBlank)

private fun continuousIntegrationBuildUrl(environment: Map<String, String>): String? =
    firstEnvironmentValue(environment, "BUILD_URL", "CIRCLE_BUILD_URL", "CI_JOB_URL")
        ?: run {
            val serverUrl = environment["GITHUB_SERVER_URL"]
            val repository = environment["GITHUB_REPOSITORY"]
            val runId = environment["GITHUB_RUN_ID"]
            if (!serverUrl.isNullOrBlank() && !repository.isNullOrBlank() && !runId.isNullOrBlank()) {
                "$serverUrl/$repository/actions/runs/$runId"
            } else {
                null
            }
        }

private fun agentName(environment: Map<String, String>): String? =
    when {
        !environment["CLAUDECODE"].isNullOrBlank() -> "Claude Code"
        !environment["CODEX_THREAD_ID"].isNullOrBlank() -> "Codex"
        !environment["CURSOR_TRACE_ID"].isNullOrBlank() -> "Cursor"
        !environment["OPENCODE"].isNullOrBlank() -> "OpenCode"
        !environment["GEMINI_CLI"].isNullOrBlank() -> "Gemini CLI"
        else -> null
    }

private fun tagSegment(value: String): String =
    value
        .lowercase(Locale.ROOT)
        .replace(Regex("[^a-z0-9_-]+"), "-")
        .trim('-')

internal fun buildCustomMetadata(
    environment: Map<String, String> = System.getenv(),
    configuredTags: Iterable<String> = emptyList(),
    configuredValues: Map<String, String> = emptyMap(),
    systemMetadataProvider: BuildSystemMetadataProvider = DefaultBuildSystemMetadataProvider(),
    automaticMetadataEnabled: Boolean = true,
    commonCustomUserDataPluginApplied: Boolean = false,
    ciDetector: CIDetector = EnvironmentCIDetector(),
    gitInfoProvider: GitInfoProvider = ProcessGitInfoProvider(),
    systemPropertyProvider: (String) -> String? = System::getProperty
): BuildCustomMetadata {
    val environmentTags =
        environment["TUIST_BUILD_TAGS"]
            ?.split(',')
            .orEmpty()
            .map(String::trim)
            .filter(String::isNotEmpty)

    val environmentValues =
        environment
            .filterKeys { it.startsWith("TUIST_BUILD_VALUE_") }
            .mapKeys { (key, _) -> key.removePrefix("TUIST_BUILD_VALUE_").lowercase(Locale.ROOT) }

    return BuildCustomMetadata(
        tags = normalizeBuildMetadataTags(environmentTags + configuredTags),
        values =
            mergeBuildMetadataValues(
                configuredValues,
                environmentValues
            )
    )
}

private fun normalizeBuildMetadataTags(tags: Iterable<String>): List<String> =
    tags
        .asSequence()
        .map(String::trim)
        .filter(String::isNotEmpty)
        .filter { it.length <= MAX_BUILD_METADATA_TAG_LENGTH && validBuildMetadataTag.matches(it) }
        .distinct()
        .take(MAX_BUILD_METADATA_TAGS)
        .toList()

private fun normalizeBuildMetadataValues(values: Map<String, String>): Map<String, String> =
    values.filter { (key, value) ->
        key.isNotBlank() &&
            key.length <= MAX_BUILD_METADATA_KEY_LENGTH &&
            value.length <= MAX_BUILD_METADATA_VALUE_LENGTH
    }

private fun mergeBuildMetadataValues(vararg sources: Map<String, String>): Map<String, String> =
    buildMap {
        sources.forEach { source ->
            normalizeBuildMetadataValues(source).forEach { (key, value) -> putIfAbsent(key, value) }
        }
    }.entries.take(MAX_BUILD_METADATA_VALUES).associate { it.toPair() }
