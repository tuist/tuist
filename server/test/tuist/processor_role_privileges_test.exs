defmodule Tuist.ProcessorRolePrivilegesTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Bazel
  alias Tuist.Bazel.TestInvocation
  alias Tuist.Bazel.Workers.ProcessTestInvocationWorker
  alias Tuist.Builds.Workers.ProcessBuildWorker
  alias Tuist.Processor.BuildProcessor
  alias Tuist.Processor.XCResultProcessor
  alias Tuist.Tests.Workers.ProcessXcresultWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.ProcessorRole

  setup :verify_on_exit!

  @storage_key "tuist/builds/test-archive.zip"

  setup do
    %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture()

    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: account.id,
        status: "processing",
        duration: 0
      )

    %{account: account, project: project, build: build}
  end

  test "the build ingestion path only reads and writes granted tables", %{
    account: account,
    project: project,
    build: build
  } do
    stub(Tuist.Storage, :download_to_file, fn @storage_key, _path, _account -> {:ok, :done} end)

    stub(BuildProcessor, :process_build, fn _path, _upload_enabled, consume ->
      consume.(%{
        "duration" => 1200,
        "status" => "success",
        "targets" => [],
        "issues" => [],
        "files" => [],
        "cacheable_tasks" => [],
        "cas_outputs" => [],
        "build_steps" => [],
        "machine_metrics" => []
      })
    end)

    job = %Oban.Job{
      args: %{
        "build_id" => build.id,
        "storage_key" => @storage_key,
        "account_id" => account.id,
        "project_id" => project.id,
        "xcode_cache_upload_enabled" => true
      },
      attempt: 1,
      max_attempts: 5
    }

    assert :ok == ProcessorRole.as_processor(fn -> ProcessBuildWorker.perform(job) end)
  end

  test "the xcresult ingestion path only reads and writes granted tables", %{
    account: account,
    project: project
  } do
    stub(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)

    stub(XCResultProcessor, :process_local, fn _path, _opts ->
      {:ok,
       %{
         "test_plan_name" => "AppTests",
         "status" => "success",
         "duration" => 45,
         "test_modules" => []
       }}
    end)

    job = %Oban.Job{
      args: %{
        "test_run_id" => Ecto.UUID.generate(),
        "storage_key" => "tuist/tests/test-xcresult.zip",
        "account_id" => account.id,
        "project_id" => project.id,
        "account_handle" => "test-account",
        "project_handle" => "test-project",
        "is_ci" => false,
        "git_branch" => "main",
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/heads/main",
        "macos_version" => "15.0",
        "xcode_version" => "16.0",
        "model_identifier" => "Mac15,3",
        "scheme" => "App"
      },
      attempt: 1,
      max_attempts: 20
    }

    assert :ok == ProcessorRole.as_processor(fn -> ProcessXcresultWorker.perform(job) end)
  end

  test "the Bazel test ingestion path only reads and writes granted tables", %{project: project} do
    project = Repo.preload(project, :account)
    invocation_id = "invocation-1"

    Bazel.create_invocations([
      %{
        invocation_id: invocation_id,
        command: "test",
        target_patterns: ["//..."],
        status: "success",
        exit_code: 0,
        started_at: ~N[2026-09-09 12:00:00],
        finished_at: ~N[2026-09-09 12:00:15],
        duration_ms: 15_000,
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])

    Repo.insert!(%TestInvocation{
      id: UUIDv7.generate(),
      project_id: project.id,
      invocation_id: invocation_id,
      state: "pending",
      test_run_id: Ecto.UUID.generate()
    })

    job = %Oban.Job{
      args: %{"project_id" => project.id, "invocation_id" => invocation_id},
      attempt: 1,
      max_attempts: 40
    }

    assert :ok == ProcessorRole.as_processor(fn -> ProcessTestInvocationWorker.perform(job) end)
  end
end
