package dev.tuist.app.data.auth;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import okhttp3.OkHttpClient;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata
@DaggerGenerated
@Generated(
    value = "dagger.internal.codegen.ComponentProcessor",
    comments = "https://dagger.dev"
)
@SuppressWarnings({
    "unchecked",
    "rawtypes",
    "KotlinInternal",
    "KotlinInternalInJava",
    "cast",
    "deprecation",
    "nullness:initialization.field.uninitialized"
})
public final class AuthRepository_Factory implements Factory<AuthRepository> {
  private final Provider<TokenStorage> tokenStorageProvider;

  private final Provider<OkHttpClient> okHttpClientProvider;

  public AuthRepository_Factory(Provider<TokenStorage> tokenStorageProvider,
      Provider<OkHttpClient> okHttpClientProvider) {
    this.tokenStorageProvider = tokenStorageProvider;
    this.okHttpClientProvider = okHttpClientProvider;
  }

  @Override
  public AuthRepository get() {
    return newInstance(tokenStorageProvider.get(), okHttpClientProvider.get());
  }

  public static AuthRepository_Factory create(Provider<TokenStorage> tokenStorageProvider,
      Provider<OkHttpClient> okHttpClientProvider) {
    return new AuthRepository_Factory(tokenStorageProvider, okHttpClientProvider);
  }

  public static AuthRepository newInstance(TokenStorage tokenStorage, OkHttpClient okHttpClient) {
    return new AuthRepository(tokenStorage, okHttpClient);
  }
}
