defmodule TuistTestSupport.Fixtures.GradleFixtures do
  @moduledoc """
  Fixtures for Gradle builds and cache events.
  """

  alias Tuist.Gradle
  alias Tuist.Gradle.CacheEvent
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def build_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    account_id =
      Keyword.get_lazy(attrs, :account_id, fn ->
        AccountsFixtures.user_fixture(preload: [:account]).account.id
      end)

    {:ok, build_id} =
      Gradle.create_build(%{
        project_id: project_id,
        account_id: account_id,
        duration_ms: Keyword.get(attrs, :duration_ms, 10_000),
        status: Keyword.get(attrs, :status, "success"),
        gradle_version: Keyword.get(attrs, :gradle_version, "8.5"),
        java_version: Keyword.get(attrs, :java_version, "17.0.1"),
        is_ci: Keyword.get(attrs, :is_ci, false),
        git_branch: Keyword.get(attrs, :git_branch),
        git_commit_sha: Keyword.get(attrs, :git_commit_sha),
        git_ref: Keyword.get(attrs, :git_ref),
        inserted_at: Keyword.get(attrs, :inserted_at),
        tasks: Keyword.get(attrs, :tasks, [])
      })

    build_id
  end

  def cache_event_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    now =
      Keyword.get(attrs, :inserted_at, NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second))

    event = %{
      id: Keyword.get_lazy(attrs, :id, fn -> UUIDv7.generate() end),
      action: Keyword.get(attrs, :action, "upload"),
      cache_key: Keyword.get(attrs, :cache_key, "cache_key_#{:rand.uniform(100_000)}"),
      size: Keyword.get(attrs, :size, 1_000_000),
      duration_ms: Keyword.get(attrs, :duration_ms, 100),
      is_hit: Keyword.get(attrs, :is_hit, true),
      project_id: project_id,
      account_handle: Keyword.get(attrs, :account_handle, "test-account"),
      project_handle: Keyword.get(attrs, :project_handle, "test-project"),
      inserted_at: now
    }

    {1, _} = IngestRepo.insert_all(CacheEvent, [event])

    event
  end
end
