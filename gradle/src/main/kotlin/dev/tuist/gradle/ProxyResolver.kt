package dev.tuist.gradle

import java.io.File

/**
 * Resolves the effective [Proxy] configuration by merging the DSL-provided
 * proxy with whatever is in `tuist.toml`.
 *
 * Precedence:
 *  1. The DSL-provided proxy, if it isn't [Proxy.None].
 *  2. The `[proxy]` table in the nearest `tuist.toml`, if any.
 *  3. [Proxy.None].
 *
 * Keeping this in one place means every HTTP-using call site in the plugin
 * goes through the same merge logic — no `if (toml != null) ... else ...`
 * scattered across the codebase.
 */
object ProxyResolver {
    fun resolve(extensionProxy: Proxy, projectDir: File?): Proxy {
        if (extensionProxy !is Proxy.None) return extensionProxy
        if (projectDir == null) return Proxy.None
        val tomlFile = ServerUrlResolver.findTomlFile(projectDir) ?: return Proxy.None
        val toml = TomlParser.parse(tomlFile) ?: return Proxy.None
        val tomlProxy = toml.proxy ?: return Proxy.None
        return when {
            !tomlProxy.url.isNullOrBlank() -> Proxy.Url(tomlProxy.url)
            tomlProxy.environmentVariable != null -> Proxy.EnvironmentVariable(tomlProxy.environmentVariable)
            else -> Proxy.None
        }
    }
}
