defmodule TuistTestSupport.Fixtures.RunsFixtures do
  @moduledoc """
  Fixtures for runs.
  """
  alias Ecto.Adapters.SQL
  alias Tuist.Builds
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseEvent
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def optimize_test_case_runs do
    SQL.query!(IngestRepo, "OPTIMIZE TABLE test_case_runs FINAL", [])
  end

  def build_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    account_id =
      Keyword.get_lazy(attrs, :user_id, fn ->
        AccountsFixtures.user_fixture(preload: [:account]).account.id
      end)

    result =
      Builds.create_build(%{
        id: Keyword.get(attrs, :id, UUIDv7.generate()),
        duration: Keyword.get(attrs, :duration, 1000),
        macos_version: Keyword.get(attrs, :macos_version, "11.2.3"),
        xcode_version: Keyword.get(attrs, :xcode_version, "12.4"),
        is_ci: Keyword.get(attrs, :is_ci, false),
        model_identifier: Keyword.get(attrs, :model_identifier, "Mac15,6"),
        scheme: Keyword.get(attrs, :scheme, "App"),
        configuration: Keyword.get(attrs, :configuration, "Debug"),
        project_id: project_id,
        account_id: account_id,
        inserted_at: Keyword.get(attrs, :inserted_at),
        status: Keyword.get(attrs, :status, :success),
        category: Keyword.get(attrs, :category, :incremental),
        git_commit_sha: Keyword.get(attrs, :git_commit_sha),
        git_branch: Keyword.get(attrs, :git_branch),
        git_ref: Keyword.get(attrs, :git_ref),
        ci_run_id: Keyword.get(attrs, :ci_run_id),
        ci_project_handle: Keyword.get(attrs, :ci_project_handle),
        ci_host: Keyword.get(attrs, :ci_host),
        ci_provider: Keyword.get(attrs, :ci_provider),
        issues: Keyword.get(attrs, :issues, []),
        files: Keyword.get(attrs, :files, []),
        targets: Keyword.get(attrs, :targets, []),
        cacheable_tasks: Keyword.get(attrs, :cacheable_tasks, []),
        cas_outputs: Keyword.get(attrs, :cas_outputs, []),
        cacheable_tasks_count: Keyword.get(attrs, :cacheable_tasks_count),
        cacheable_task_local_hits_count: Keyword.get(attrs, :cacheable_task_local_hits_count),
        cacheable_task_remote_hits_count: Keyword.get(attrs, :cacheable_task_remote_hits_count),
        custom_tags: Keyword.get(attrs, :custom_tags, []),
        custom_values: Keyword.get(attrs, :custom_values, %{})
      })

    Tuist.Builds.Build.Buffer.flush()
    result
  end

  def test_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    account_id =
      Keyword.get_lazy(attrs, :account_id, fn ->
        AccountsFixtures.user_fixture(preload: [:account]).account.id
      end)

    test_modules =
      Keyword.get(attrs, :test_modules, [
        %{
          name: "TestModuleExample",
          status: "success",
          duration: 1000,
          test_cases: [
            %{
              name: "testExample",
              status: "success",
              duration: 500
            },
            %{
              name: "testAnotherExample",
              status: "failure",
              duration: 300
            }
          ]
        }
      ])

    Tests.create_test(%{
      id: Keyword.get(attrs, :id, UUIDv7.generate()),
      project_id: project_id,
      account_id: account_id,
      duration: Keyword.get(attrs, :duration, 2000),
      status: Keyword.get(attrs, :status, "success"),
      scheme: Keyword.get(attrs, :scheme),
      model_identifier: Keyword.get(attrs, :model_identifier, "Mac15,6"),
      macos_version: Keyword.get(attrs, :macos_version, "11.2.3"),
      xcode_version: Keyword.get(attrs, :xcode_version, "12.4"),
      git_branch: Keyword.get(attrs, :git_branch, "main"),
      git_ref: Keyword.get(attrs, :git_ref),
      git_commit_sha: Keyword.get(attrs, :git_commit_sha, "abc123"),
      ran_at: Keyword.get(attrs, :ran_at, NaiveDateTime.utc_now()),
      is_ci: Keyword.get(attrs, :is_ci, false),
      build_run_id: Keyword.get(attrs, :build_run_id),
      ci_run_id: Keyword.get(attrs, :ci_run_id),
      ci_project_handle: Keyword.get(attrs, :ci_project_handle),
      ci_host: Keyword.get(attrs, :ci_host),
      ci_provider: Keyword.get(attrs, :ci_provider),
      test_modules: test_modules
    })
  end

  def cas_output_fixture(attrs \\ []) do
    build_run_id =
      Keyword.get_lazy(attrs, :build_run_id, fn ->
        {:ok, build} = build_fixture()
        build.id
      end)

    cas_output = %{
      node_id: Keyword.get(attrs, :node_id, "node1"),
      checksum: Keyword.get(attrs, :checksum, "abc123"),
      size: Keyword.get(attrs, :size, 1000),
      duration: Keyword.get(attrs, :duration, 100),
      compressed_size: Keyword.get(attrs, :compressed_size, 800),
      operation: Keyword.get(attrs, :operation, :download),
      type: Keyword.get(attrs, :type, :swift)
    }

    changeset = Tuist.Builds.CASOutput.changeset(build_run_id, cas_output)

    IngestRepo.insert(changeset)
  end

  def test_case_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    %TestCase{
      id: Keyword.get_lazy(attrs, :id, fn -> UUIDv7.generate() end),
      name: Keyword.get(attrs, :name, "testExample"),
      module_name: Keyword.get(attrs, :module_name, "MyTests"),
      suite_name: Keyword.get(attrs, :suite_name, "TestSuite"),
      project_id: project_id,
      last_status: Keyword.get(attrs, :last_status, "success"),
      last_duration: Keyword.get(attrs, :last_duration, 100),
      last_ran_at: Keyword.get(attrs, :last_ran_at, NaiveDateTime.utc_now()),
      is_flaky: Keyword.get(attrs, :is_flaky, false),
      is_quarantined: Keyword.get(attrs, :is_quarantined, false),
      inserted_at: Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now()),
      avg_duration: Keyword.get(attrs, :avg_duration, 100)
    }
  end

  def test_case_run_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    test_case_run = %{
      id: Keyword.get_lazy(attrs, :id, fn -> UUIDv7.generate() end),
      test_run_id: Keyword.get_lazy(attrs, :test_run_id, fn -> UUIDv7.generate() end),
      test_module_run_id: Keyword.get_lazy(attrs, :test_module_run_id, fn -> UUIDv7.generate() end),
      test_case_id: Keyword.get_lazy(attrs, :test_case_id, fn -> UUIDv7.generate() end),
      project_id: project_id,
      git_branch: Keyword.get(attrs, :git_branch, "main"),
      module_name: Keyword.get(attrs, :module_name, "MyTests"),
      suite_name: Keyword.get(attrs, :suite_name, "TestSuite"),
      name: Keyword.get(attrs, :name, "testExample"),
      status: Keyword.get(attrs, :status, 0),
      is_flaky: Keyword.get(attrs, :is_flaky, false),
      is_new: Keyword.get(attrs, :is_new, false),
      duration: Keyword.get(attrs, :duration, 100),
      ran_at: Keyword.get(attrs, :ran_at, NaiveDateTime.utc_now()),
      inserted_at: Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    }

    {1, _} = IngestRepo.insert_all(TestCaseRun, [test_case_run])

    test_case_run
  end

  def test_case_event_fixture(attrs \\ []) do
    test_case_event = %{
      id: Keyword.get_lazy(attrs, :id, fn -> UUIDv7.generate() end),
      test_case_id: Keyword.fetch!(attrs, :test_case_id),
      event_type: Keyword.get(attrs, :event_type, "quarantined"),
      actor_id: Keyword.get(attrs, :actor_id, nil),
      inserted_at: Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    }

    {1, _} = IngestRepo.insert_all(TestCaseEvent, [test_case_event])

    test_case_event
  end
end
