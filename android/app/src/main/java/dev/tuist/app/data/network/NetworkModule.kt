package dev.tuist.app.data.network

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dev.tuist.app.BuildConfig
import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.data.EnvironmentConfig
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideMoshi(): Moshi = Moshi.Builder()
        .addLast(KotlinJsonAdapterFactory())
        .build()

    @Provides
    @Singleton
    @PlainClient
    fun providePlainOkHttpClient(): OkHttpClient {
        val builder = OkHttpClient.Builder()

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
        val builder = OkHttpClient.Builder()
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
}
