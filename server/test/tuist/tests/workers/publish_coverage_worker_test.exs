defmodule Tuist.Tests.Workers.PublishCoverageWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Workers.PublishCoverageWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
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

    assert CoverageFixtures.run_summary(project.id, run.id) == %{covered_lines: 2, executable_lines: 3, partial: true}
    assert [] = Path.wildcard(Path.join(System.tmp_dir!(), "coverage_*.ndjson"))
  end

  describe "an upload that cannot be published" do
    setup do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      {:ok, run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      %{account: account, project: project, run: run}
    end

    @tag :tmp_dir
    test "is cancelled when it inflates past the limit", %{tmp_dir: tmp_dir} = context do
      stub(Environment, :coverage_max_inflated_bytes, fn -> 100 end)
      upload = write_upload(tmp_dir, deflate(String.duplicate(file_line("Sources/A.swift"), 5)))

      assert {:cancel, :coverage_too_large} = perform_upload(context, upload)
      assert CoverageFixtures.run_summary(context.project.id, context.run.id) == nil
      assert [] = Path.wildcard(Path.join(System.tmp_dir!(), "coverage_*.ndjson"))
    end

    @tag :tmp_dir
    test "is cancelled when the stream was cut off", %{tmp_dir: tmp_dir} = context do
      z = :zlib.open()
      :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
      first = IO.iodata_to_binary(:zlib.deflate(z, file_line("Sources/A.swift"), :sync))
      second = IO.iodata_to_binary(:zlib.deflate(z, file_line("Sources/B.swift"), :sync))
      :zlib.close(z)
      upload = write_upload(tmp_dir, first <> binary_part(second, 0, div(byte_size(second), 2)))

      assert {:cancel, :truncated_coverage} = perform_upload(context, upload)
      assert CoverageFixtures.run_summary(context.project.id, context.run.id) == nil
    end

    @tag :tmp_dir
    test "is cancelled when it is not DEFLATE", %{tmp_dir: tmp_dir} = context do
      upload = write_upload(tmp_dir, <<0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x01>>)

      assert {:cancel, {:invalid_coverage, _}} = perform_upload(context, upload)
      assert CoverageFixtures.run_summary(context.project.id, context.run.id) == nil
    end

    @tag :tmp_dir
    test "is cancelled when a line is not JSON", %{tmp_dir: tmp_dir} = context do
      upload = write_upload(tmp_dir, deflate(file_line("Sources/A.swift") <> "{not json\n"))

      assert {:cancel, {:invalid_coverage, _}} = perform_upload(context, upload)
    end
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

  test "gives up when the run never appears" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    assert {:cancel, :test_run_not_found} =
             perform_job(
               PublishCoverageWorker,
               %{
                 "test_run_id" => UUIDv7.generate(),
                 "project_id" => project.id,
                 "account_id" => account.id,
                 "storage_key" => "k"
               },
               inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour)
             )
  end

  defp perform_upload(%{account: account, project: project, run: run}, upload) do
    key = Coverage.storage_key(Tuist.Repo.preload(project, :account), run.id)

    expect(Storage, :download_to_file, fn ^key, destination, _account ->
      File.cp!(upload, destination)
      {:ok, destination}
    end)

    perform_job(PublishCoverageWorker, %{
      "test_run_id" => run.id,
      "project_id" => project.id,
      "account_id" => account.id,
      "storage_key" => key,
      "partial" => false,
      "shard_index" => nil,
      "expected_shards" => 1
    })
  end

  defp file_line(path) do
    JSON.encode!(%{
      path: path,
      git_blob_id: String.duplicate("a", 40),
      targets: ["A"],
      is_test: false,
      covered_lines: 2,
      executable_lines: 3,
      line_numbers: [1, 2, 3],
      execution_counts: [1, 1, 0],
      functions: []
    }) <> "\n"
  end

  defp deflate(data) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    deflated = IO.iodata_to_binary([:zlib.deflate(z, data), :zlib.deflate(z, "", :finish)])
    :zlib.close(z)
    deflated
  end

  defp write_upload(tmp_dir, data) do
    path = Path.join(tmp_dir, "coverage.ndjson.deflate")
    File.write!(path, data)
    path
  end
end
