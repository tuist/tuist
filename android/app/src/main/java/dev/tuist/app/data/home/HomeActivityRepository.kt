package dev.tuist.app.data.home

import dev.tuist.app.api.HomeApi
import dev.tuist.app.data.EnvironmentConfig
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.net.URI
import javax.inject.Inject

enum class HomeActivityKind { BuildFailures, TestFailures, FlakyTests }
enum class HomeActivityFailure { Unavailable, Unsupported, Forbidden, InvalidResponse }
class HomeActivityException(val failure: HomeActivityFailure) : Exception()

data class HomeActivityItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val occurredAt: Long,
    val url: String,
)

class HomeActivityRepository @Inject constructor(
    private val api: HomeApi,
    private val environment: EnvironmentConfig,
) {
    suspend fun list(kind: HomeActivityKind, fullHandle: String): List<HomeActivityItem> {
        val handles = fullHandle.split("/")
        if (handles.size != 2 || handles.any { it.isEmpty() }) throw HomeActivityException(HomeActivityFailure.InvalidResponse)
        val response = when (kind) {
            HomeActivityKind.BuildFailures -> api.getHomeBuildFailures(handles[0], handles[1])
            HomeActivityKind.TestFailures -> api.getHomeTestFailures(handles[0], handles[1])
            HomeActivityKind.FlakyTests -> api.getHomeFlakyTests(handles[0], handles[1])
        }
        if (!response.isSuccessful) {
            throw HomeActivityException(when (response.code()) {
                403 -> HomeActivityFailure.Forbidden
                422 -> HomeActivityFailure.Unsupported
                else -> HomeActivityFailure.Unavailable
            })
        }
        val body = response.body() ?: throw HomeActivityException(HomeActivityFailure.InvalidResponse)
        return body.items.take(3).map { item ->
            val epoch = item.occurredAt.toLong()
            if (epoch <= 0 || epoch >= 253_402_300_800L) throw HomeActivityException(HomeActivityFailure.InvalidResponse)
            HomeActivityItem(item.id, item.title, item.subtitle, epoch, dashboardUrl(item.url, fullHandle))
        }
    }

    internal fun dashboardUrl(path: String, fullHandle: String): String {
        val uri = URI(path)
        if (uri.scheme != null || uri.rawAuthority != null || uri.query != null || uri.fragment != null) {
            throw HomeActivityException(HomeActivityFailure.InvalidResponse)
        }
        val base = environment.serverUrl.toHttpUrl()
        val parts = uri.path.split("/").filter { it.isNotEmpty() }
        if (parts.size < 4 || parts.take(2) != fullHandle.split("/") || parts.any { it == "." || it == ".." }) {
            throw HomeActivityException(HomeActivityFailure.InvalidResponse)
        }
        val builder = base.newBuilder()
        parts.forEach { builder.addPathSegment(it) }
        return builder.build().toString()
    }
}
