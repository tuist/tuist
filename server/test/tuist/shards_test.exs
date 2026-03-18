defmodule Tuist.ShardsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Shards
  alias Tuist.Shards.ShardPlan
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_shard_plan/3" do
    test "creates a shard plan with module-level granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :all, fn _query -> [] end)
      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id-123" end)

      stub(Tuist.IngestRepo, :insert, fn changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}
      end)

      stub(Tuist.IngestRepo, :insert_all, fn _schema, _data -> {1, nil} end)

      params = %{
        plan_id: "github-123-1",
        modules: ["AppTests", "CoreTests", "NetworkTests"],
        shard_max: 2
      }

      assert {:ok, result} = Shards.create_shard_plan(project, account, params)
      assert result.shard_count == 2
      assert result.upload_id == "upload-id-123"
      assert length(result.shard_assignments) == 2

      all_targets =
        result.shard_assignments
        |> Enum.flat_map(fn a -> a["test_targets"] end)
        |> MapSet.new()

      assert MapSet.equal?(all_targets, MapSet.new(["AppTests", "CoreTests", "NetworkTests"]))
    end

    test "uses historical timing data for bin-packing" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :all, fn _query ->
        [
          %{name: "SlowTests", avg_duration: 100_000.0},
          %{name: "FastTests", avg_duration: 10_000.0}
        ]
      end)

      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id" end)

      stub(Tuist.IngestRepo, :insert, fn changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}
      end)

      stub(Tuist.IngestRepo, :insert_all, fn _schema, _data -> {1, nil} end)

      params = %{
        plan_id: "session-1",
        modules: ["SlowTests", "FastTests", "MediumTests"],
        shard_max: 2
      }

      assert {:ok, result} = Shards.create_shard_plan(project, account, params)
      assert result.shard_count == 2
    end

    test "creates a shard plan with suite-level granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :all, fn _query -> [] end)
      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id" end)

      stub(Tuist.IngestRepo, :insert, fn changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}
      end)

      stub(Tuist.IngestRepo, :insert_all, fn _schema, _data -> {1, nil} end)

      params = %{
        plan_id: "session-2",
        test_suites: ["LoginTest", "SignupTest", "ProfileTest"],
        granularity: "suite",
        shard_max: 2
      }

      assert {:ok, result} = Shards.create_shard_plan(project, account, params)
      assert result.shard_count == 2
    end
  end

  describe "get_shard/4" do
    test "returns assignment for valid shard index with module granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      plan = %ShardPlan{
        id: Ecto.UUID.generate(),
        plan_id: "session-1",
        project_id: project.id,
        shard_count: 2,
        granularity: "module",
        inserted_at: NaiveDateTime.utc_now()
      }

      stub(Tuist.IngestRepo, :one, fn _query -> plan end)
      stub(Tuist.IngestRepo, :all, fn _query -> ["AppTests"] end)

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard(project, account, "session-1", 0)
      assert result.test_targets == ["AppTests"]
      assert result.bundle_download_url == "https://download.example.com"
    end

    test "returns error for nonexistent session" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :one, fn _query -> nil end)

      assert {:error, :not_found} =
               Shards.get_shard(project, account, "nonexistent", 0)
    end

    test "returns error for out-of-range shard index" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      plan = %ShardPlan{
        id: Ecto.UUID.generate(),
        plan_id: "session-1",
        project_id: project.id,
        shard_count: 2,
        granularity: "module",
        inserted_at: NaiveDateTime.utc_now()
      }

      stub(Tuist.IngestRepo, :one, fn _query -> plan end)
      stub(Tuist.IngestRepo, :all, fn _query -> [] end)

      assert {:error, :invalid_shard_index} =
               Shards.get_shard(project, account, "session-1", 5)
    end
  end

  describe "generate_upload_url/5" do
    test "returns upload URL" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.Storage, :multipart_generate_url, fn _key, _upload_id, _part_number, _account ->
        "https://upload.example.com/part"
      end)

      assert {:ok, url} = Shards.generate_upload_url(project, account, "session-1", "upload-id", 1)
      assert url == "https://upload.example.com/part"
    end
  end

  describe "complete_upload/5" do
    test "completes the multipart upload" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.Storage, :multipart_complete_upload, fn _key, _upload_id, _parts, _account ->
        :ok
      end)

      assert :ok =
               Shards.complete_upload(project, account, "session-1", "upload-id", [])
    end
  end
end
