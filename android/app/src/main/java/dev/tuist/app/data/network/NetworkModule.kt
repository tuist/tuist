package dev.tuist.app.data.network

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.tuist.app.BuildConfig
import dev.tuist.app.api.AISubscriptionsApi
import dev.tuist.app.api.FeatureFlagsApi
import dev.tuist.app.api.PreviewsApi
import dev.tuist.app.api.ProjectsApi
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
        .add(OffsetDateTime::class.java, OffsetDateTimeAdapter.nullSafe())
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
    fun provideFeatureFlagsApi(retrofit: Retrofit): FeatureFlagsApi =
        retrofit.create(FeatureFlagsApi::class.java)

    @Provides
    @Singleton
    fun provideAISubscriptionsApi(retrofit: Retrofit): AISubscriptionsApi =
        retrofit.create(AISubscriptionsApi::class.java)
}

/** Generated models type `date-time` fields as [OffsetDateTime], which Moshi doesn't support out of the box. */
private object OffsetDateTimeAdapter : JsonAdapter<OffsetDateTime>() {
    override fun fromJson(reader: JsonReader): OffsetDateTime = OffsetDateTime.parse(reader.nextString())

    override fun toJson(writer: JsonWriter, value: OffsetDateTime?) {
        writer.value(value?.toString())
    }
}
