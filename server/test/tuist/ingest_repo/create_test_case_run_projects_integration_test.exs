Code.require_file(
  Path.expand(
    "../../../priv/ingest_repo/migrations/20260726110000_create_test_case_run_projects.exs",
    __DIR__
  )
)

defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunProjectsIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migrations.CreateTestCaseRunProjects
  alias Tuist.Tests.TestCaseRun

  @moduletag :destructive_clickhouse_migration

  setup do
    owner = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)

    CreateTestCaseRunProjects.down()

    on_exit(fn ->
      try do
        CreateTestCaseRunProjects.up()
      after
        Sandbox.stop_owner(owner)
      end
    end)

    :ok
  end

  test "backfills existing runs, captures new runs, and is retryable" do
    existing_run = run_attrs()
    IngestRepo.insert_all(TestCaseRun, [existing_run])

    CreateTestCaseRunProjects.up()

    assert project_for_run(existing_run.id) == existing_run.project_id

    new_run = run_attrs()
    IngestRepo.insert_all(TestCaseRun, [new_run])

    assert project_for_run(new_run.id) == new_run.project_id

    CreateTestCaseRunProjects.up()

    assert project_for_run(existing_run.id) == existing_run.project_id
    assert project_for_run(new_run.id) == new_run.project_id
  end

  defp project_for_run(test_case_run_id) do
    %{rows: [[project_id]]} =
      IngestRepo.query!(
        """
        SELECT project_id
        FROM test_case_run_projects FINAL
        WHERE id = {id:UUID}
        """,
        %{id: test_case_run_id}
      )

    project_id
  end

  defp run_attrs do
    now = NaiveDateTime.utc_now()

    %{
      id: UUIDv7.generate(),
      test_run_id: UUIDv7.generate(),
      test_module_run_id: UUIDv7.generate(),
      test_case_id: UUIDv7.generate(),
      project_id: System.unique_integer([:positive, :monotonic]),
      is_ci: false,
      scheme: "",
      git_branch: "main",
      git_commit_sha: "",
      module_name: "MyTests",
      suite_name: "TestSuite",
      name: "testExample",
      status: 0,
      is_flaky: false,
      is_new: false,
      is_quarantined: false,
      duration: 100,
      ran_at: now,
      inserted_at: now
    }
  end
end
