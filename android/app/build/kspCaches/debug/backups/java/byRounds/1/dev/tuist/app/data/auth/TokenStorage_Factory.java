package dev.tuist.app.data.auth;

import android.content.Context;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata("dagger.hilt.android.qualifiers.ApplicationContext")
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
public final class TokenStorage_Factory implements Factory<TokenStorage> {
  private final Provider<Context> contextProvider;

  public TokenStorage_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public TokenStorage get() {
    return newInstance(contextProvider.get());
  }

  public static TokenStorage_Factory create(Provider<Context> contextProvider) {
    return new TokenStorage_Factory(contextProvider);
  }

  public static TokenStorage newInstance(Context context) {
    return new TokenStorage(context);
  }
}
