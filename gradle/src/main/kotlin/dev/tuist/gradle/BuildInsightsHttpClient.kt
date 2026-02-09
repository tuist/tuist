package dev.tuist.gradle

import com.google.gson.Gson
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI

interface BuildInsightsHttpClient {
    fun postBuildReport(url: URI, token: String, report: BuildReportRequest): BuildReportResponse?
}

class UrlConnectionBuildInsightsHttpClient : BuildInsightsHttpClient {
    private val gson = Gson()

    override fun postBuildReport(url: URI, token: String, report: BuildReportRequest): BuildReportResponse? {
        val connection = url.toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $token")

            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                gson.toJson(report, writer)
            }

            return when (connection.responseCode) {
                HttpURLConnection.HTTP_CREATED -> {
                    BufferedReader(InputStreamReader(connection.inputStream, Charsets.UTF_8)).use { reader ->
                        gson.fromJson(reader, BuildReportResponse::class.java)
                    }
                }
                else -> null
            }
        } finally {
            connection.disconnect()
        }
    }
}
