package dev.tuist.app.data.network;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import dev.tuist.app.data.auth.TokenStorage;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
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
public final class AuthInterceptor_Factory implements Factory<AuthInterceptor> {
  private final Provider<TokenStorage> tokenStorageProvider;

  public AuthInterceptor_Factory(Provider<TokenStorage> tokenStorageProvider) {
    this.tokenStorageProvider = tokenStorageProvider;
  }

  @Override
  public AuthInterceptor get() {
    return newInstance(tokenStorageProvider.get());
  }

  public static AuthInterceptor_Factory create(Provider<TokenStorage> tokenStorageProvider) {
    return new AuthInterceptor_Factory(tokenStorageProvider);
  }

  public static AuthInterceptor newInstance(TokenStorage tokenStorage) {
    return new AuthInterceptor(tokenStorage);
  }
}
