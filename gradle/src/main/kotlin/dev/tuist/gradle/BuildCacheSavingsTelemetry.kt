package dev.tuist.gradle

/** Cumulative task work avoided, not elapsed build time saved. */
internal class BuildCacheSavingsTelemetry {
    private var savingsMs = 0L
    private var complete = true

    fun cachedTask(originalExecutionMs: Long?, restoreMs: Long) {
        if (originalExecutionMs == null || originalExecutionMs < 0 || restoreMs < 0) {
            markIncomplete()
            return
        }
        val saved = (originalExecutionMs - restoreMs).coerceAtLeast(0)
        if (saved > MAX_SAVINGS_MS - savingsMs) markIncomplete() else savingsMs += saved
    }

    fun markIncomplete() { complete = false }

    fun metadata(metadata: BuildCustomMetadata): BuildCustomMetadata {
        if (!complete || metadata.values.size >= MAX_BUILD_METADATA_VALUES || KEY in metadata.values) return metadata
        return metadata.copy(values = metadata.values + (KEY to savingsMs.toString()))
    }

    companion object {
        const val KEY = "tuist.cache_work_avoided_ms"
        private const val MAX_SAVINGS_MS = 31_536_000_000L
    }
}
