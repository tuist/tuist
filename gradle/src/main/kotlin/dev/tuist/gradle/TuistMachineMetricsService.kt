package dev.tuist.gradle

import org.gradle.api.model.ObjectFactory
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import org.gradle.internal.time.Time
import javax.inject.Inject

abstract class TuistMachineMetricsService : BuildService<BuildServiceParameters.None>, AutoCloseable {
    @get:Inject
    abstract val objects: ObjectFactory

    private val collector = MachineMetricsCollector(
        inputTrackingState = objects.newInstance(MetricsInputTracking::class.java).state,
        currentTimeMillis = Time::currentTimeMillis
    ).also { it.start() }

    private var reportingOwnsCollector = false

    @Synchronized
    fun attachReporter() {
        reportingOwnsCollector = true
    }

    @Synchronized
    fun finish(): List<MachineMetricSample> {
        reportingOwnsCollector = false
        return collector.stop()
    }

    @Synchronized
    override fun close() {
        // The operation listener drains its queued completions before closing. Keep
        // sampling until that owner finishes, regardless of Gradle's service stop order.
        if (!reportingOwnsCollector) collector.stop()
    }
}
