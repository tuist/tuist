package dev.tuist.app.ui.projects;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import dev.tuist.app.data.auth.AuthRepository;
import dev.tuist.app.data.projects.ProjectsRepository;
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
public final class ProjectsViewModel_Factory implements Factory<ProjectsViewModel> {
  private final Provider<ProjectsRepository> projectsRepositoryProvider;

  private final Provider<AuthRepository> authRepositoryProvider;

  public ProjectsViewModel_Factory(Provider<ProjectsRepository> projectsRepositoryProvider,
      Provider<AuthRepository> authRepositoryProvider) {
    this.projectsRepositoryProvider = projectsRepositoryProvider;
    this.authRepositoryProvider = authRepositoryProvider;
  }

  @Override
  public ProjectsViewModel get() {
    return newInstance(projectsRepositoryProvider.get(), authRepositoryProvider.get());
  }

  public static ProjectsViewModel_Factory create(
      Provider<ProjectsRepository> projectsRepositoryProvider,
      Provider<AuthRepository> authRepositoryProvider) {
    return new ProjectsViewModel_Factory(projectsRepositoryProvider, authRepositoryProvider);
  }

  public static ProjectsViewModel newInstance(ProjectsRepository projectsRepository,
      AuthRepository authRepository) {
    return new ProjectsViewModel(projectsRepository, authRepository);
  }
}
