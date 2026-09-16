defmodule Tuist.Tests.Workers.PublishCoverageWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Workers.PublishCoverageWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @tag :tmp_dir
  test "inflates the uploaded coverage and publishes it for the run", %{tmp_dir: tmp_dir} do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    {:ok, run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)

    ndjson =
      JSON.encode!(%{
        path: "Sources/A.swift",
        git_blob_id: String.duplicate("a", 40),
        targets: ["A"],
        is_test: false,
        covered_lines: 2,
        executable_lines: 3,
        line_numbers: [1, 2, 3],
        execution_counts: [1, 1, 0],
        functions: []
      }) <> "\n"

    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    deflated = IO.iodata_to_binary([:zlib.deflate(z, ndjson), :zlib.deflate(z, "", :finish)])
    :zlib.close(z)
    upload = Path.join(tmp_dir, "coverage.ndjson.deflate")
    File.write!(upload, deflated)

    key = Coverage.storage_key(Tuist.Repo.preload(project, :account), run.id)

    expect(Storage, :download_to_file, fn ^key, destination, _account ->
      File.cp!(upload, destination)
      {:ok, destination}
    end)

    assert :ok =
             perform_job(PublishCoverageWorker, %{
               "test_run_id" => run.id,
               "project_id" => project.id,
               "account_id" => account.id,
               "storage_key" => key,
               "partial" => true,
               "shard_index" => nil,
               "expected_shards" => 1
             })

    assert Coverage.run_summary(project.id, run.id) == %{covered_lines: 2, executable_lines: 3, partial: true}
    assert [] = Path.wildcard(Path.join(System.tmp_dir!(), "coverage_*.ndjson"))
  end

  test "snoozes until the run exists" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    assert {:snooze, 30} =
             perform_job(PublishCoverageWorker, %{
               "test_run_id" => UUIDv7.generate(),
               "project_id" => project.id,
               "account_id" => account.id,
               "storage_key" => "k"
             })
  end
end
