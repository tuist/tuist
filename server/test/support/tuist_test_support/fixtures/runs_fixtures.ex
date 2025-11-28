defmodule TuistTestSupport.Fixtures.RunsFixtures do
  @moduledoc """
  Fixtures for runs.
  """
  alias Tuist.Runs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def build_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    account_id =
      Keyword.get_lazy(attrs, :user_id, fn ->
        AccountsFixtures.user_fixture(preload: [:account]).account.id
      end)

    Runs.create_build(%{
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
      cas_outputs: Keyword.get(attrs, :cas_outputs, [])
    })
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

    Runs.create_test(%{
      id: Keyword.get(attrs, :id, UUIDv7.generate()),
      project_id: project_id,
      account_id: account_id,
      duration: Keyword.get(attrs, :duration, 2000),
      status: Keyword.get(attrs, :status, "success"),
      model_identifier: Keyword.get(attrs, :model_identifier, "Mac15,6"),
      macos_version: Keyword.get(attrs, :macos_version, "11.2.3"),
      xcode_version: Keyword.get(attrs, :xcode_version, "12.4"),
      git_branch: Keyword.get(attrs, :git_branch, "main"),
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

    changeset = Tuist.Runs.CASOutput.changeset(build_run_id, cas_output)

    Tuist.IngestRepo.insert(changeset)
  end
end
