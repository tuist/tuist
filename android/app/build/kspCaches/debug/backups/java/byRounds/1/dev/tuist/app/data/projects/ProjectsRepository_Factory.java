package dev.tuist.app.data.projects;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import dev.tuist.app.data.network.TuistApiService;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class ProjectsRepository_Factory implements Factory<ProjectsRepository> {
  private final Provider<TuistApiService> apiServiceProvider;

  public ProjectsRepository_Factory(Provider<TuistApiService> apiServiceProvider) {
    this.apiServiceProvider = apiServiceProvider;
  }

  @Override
  public ProjectsRepository get() {
    return newInstance(apiServiceProvider.get());
  }

  public static ProjectsRepository_Factory create(Provider<TuistApiService> apiServiceProvider) {
    return new ProjectsRepository_Factory(apiServiceProvider);
  }

  public static ProjectsRepository newInstance(TuistApiService apiService) {
    return new ProjectsRepository(apiService);
  }
}
