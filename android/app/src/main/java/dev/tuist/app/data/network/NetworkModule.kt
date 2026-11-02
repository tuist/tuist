package dev.tuist.app.data.network

import com.squareup.moshi.FromJson
import com.squareup.moshi.Moshi
import com.squareup.moshi.ToJson
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.tuist.app.BuildConfig
import dev.tuist.app.api.NotificationPreferencesApi
import dev.tuist.app.api.PreviewsApi
import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.PushDevicesApi
import dev.tuist.app.data.EnvironmentConfig
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import java.time.OffsetDateTime
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideMoshi(): Moshi = Moshi.Builder()
        .add(OffsetDateTimeAdapter)
        .addLast(KotlinJsonAdapterFactory())
        .build()

    @Provides
    @Singleton
    @PlainClient
    fun providePlainOkHttpClient(): OkHttpClient {
        val builder = CertificateTrust.clientBuilder()

        if (BuildConfig.DEBUG) {
            val logging = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BODY
            }
            builder.addInterceptor(logging)
        }

        return builder.build()
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(
        requestIdInterceptor: RequestIdInterceptor,
        authInterceptor: AuthInterceptor,
        tokenRefreshAuthenticator: TokenRefreshAuthenticator,
    ): OkHttpClient {
        val builder = CertificateTrust.clientBuilder()
            .addInterceptor(requestIdInterceptor)
            .addInterceptor(authInterceptor)
            .authenticator(tokenRefreshAuthenticator)

        if (BuildConfig.DEBUG) {
            val logging = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BODY
            }
            builder.addInterceptor(logging)
        }

        return builder.build()
    }

    @Provides
    @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient, moshi: Moshi, environmentConfig: EnvironmentConfig): Retrofit =
        Retrofit.Builder()
            .baseUrl(environmentConfig.serverUrl.trimEnd('/') + "/")
            .client(okHttpClient)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()

    @Provides
    @Singleton
    fun provideProjectsApi(retrofit: Retrofit): ProjectsApi =
        retrofit.create(ProjectsApi::class.java)

    @Provides
    @Singleton
    fun providePreviewsApi(retrofit: Retrofit): PreviewsApi =
        retrofit.create(PreviewsApi::class.java)

    @Provides
    @Singleton
    fun providePushDevicesApi(retrofit: Retrofit): PushDevicesApi =
        retrofit.create(PushDevicesApi::class.java)

    @Provides
    @Singleton
    fun provideNotificationPreferencesApi(retrofit: Retrofit): NotificationPreferencesApi =
        retrofit.create(NotificationPreferencesApi::class.java)
}

internal object OffsetDateTimeAdapter {
    @ToJson
    fun toJson(value: OffsetDateTime): String = value.toString()

    @FromJson
    fun fromJson(value: String): OffsetDateTime = OffsetDateTime.parse(value)
}
