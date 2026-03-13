defmodule Tuist.ShardsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Shards
  alias Tuist.Shards.ShardSession
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_shard_session/3" do
    test "creates a shard session with module-level granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :all, fn _query -> [] end)
      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id-123" end)

      stub(Tuist.IngestRepo, :insert, fn changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}
      end)

      params = %{
        session_id: "github-123-1",
        modules: ["AppTests", "CoreTests", "NetworkTests"],
        shard_max: 2
      }

      assert {:ok, result} = Shards.create_shard_session(project, account, params)
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

      params = %{
        session_id: "session-1",
        modules: ["SlowTests", "FastTests", "MediumTests"],
        shard_max: 2
      }

      assert {:ok, result} = Shards.create_shard_session(project, account, params)
      assert result.shard_count == 2
    end

    test "creates a shard session with suite-level granularity" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :all, fn _query -> [] end)
      stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id" end)

      stub(Tuist.IngestRepo, :insert, fn changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}
      end)

      params = %{
        session_id: "session-2",
        test_suites: ["LoginTest", "SignupTest", "ProfileTest"],
        granularity: "suite",
        shard_max: 2
      }

      assert {:ok, result} = Shards.create_shard_session(project, account, params)
      assert result.shard_count == 2
    end
  end

  describe "get_shard_assignment/4" do
    test "returns assignment for valid shard index" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      session = %ShardSession{
        id: Ecto.UUID.generate(),
        session_id: "session-1",
        project_id: project.id,
        shard_count: 2,
        granularity: "module",
        shard_assignments:
          Jason.encode!([
            %{"index" => 0, "test_targets" => ["AppTests"], "estimated_duration_ms" => 100},
            %{"index" => 1, "test_targets" => ["CoreTests"], "estimated_duration_ms" => 80}
          ]),
        bundle_object_key: "bundle.zip",
        xctestrun_object_key: "original.xctestrun",
        upload_completed: 1,
        inserted_at: NaiveDateTime.utc_now()
      }

      stub(Tuist.IngestRepo, :one, fn _query -> session end)

      stub(Tuist.Storage, :generate_download_url, fn _key, _account ->
        "https://download.example.com"
      end)

      assert {:ok, result} = Shards.get_shard_assignment(project, account, "session-1", 0)
      assert result.test_targets == ["AppTests"]
      assert result.xctestrun_download_url == "https://download.example.com"
      assert result.bundle_download_url == "https://download.example.com"
    end

    test "returns error for nonexistent session" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :one, fn _query -> nil end)

      assert {:error, :not_found} =
               Shards.get_shard_assignment(project, account, "nonexistent", 0)
    end

    test "returns error for out-of-range shard index" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      session = %ShardSession{
        id: Ecto.UUID.generate(),
        session_id: "session-1",
        project_id: project.id,
        shard_count: 2,
        shard_assignments:
          Jason.encode!([
            %{"index" => 0, "test_targets" => ["AppTests"], "estimated_duration_ms" => 100}
          ]),
        bundle_object_key: "bundle.zip",
        xctestrun_object_key: "original.xctestrun",
        inserted_at: NaiveDateTime.utc_now()
      }

      stub(Tuist.IngestRepo, :one, fn _query -> session end)

      assert {:error, :invalid_shard_index} =
               Shards.get_shard_assignment(project, account, "session-1", 5)
    end
  end

  describe "complete_upload/5" do
    test "marks session as completed and creates per-shard xctestrun files" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      session = %ShardSession{
        id: Ecto.UUID.generate(),
        session_id: "session-1",
        project_id: project.id,
        shard_count: 2,
        granularity: "module",
        shard_assignments:
          Jason.encode!([
            %{"index" => 0, "test_targets" => ["AppTests"], "estimated_duration_ms" => 100},
            %{"index" => 1, "test_targets" => ["CoreTests"], "estimated_duration_ms" => 80}
          ]),
        bundle_object_key: "bundle.zip",
        xctestrun_object_key: "original.xctestrun",
        upload_completed: 0,
        inserted_at: NaiveDateTime.utc_now()
      }

      sample_xctestrun = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>TestConfigurations</key>
        <array>
          <dict>
            <key>Name</key>
            <string>Default</string>
            <key>TestTargets</key>
            <array>
              <dict>
                <key>BlueprintName</key>
                <string>AppTests</string>
              </dict>
              <dict>
                <key>BlueprintName</key>
                <string>CoreTests</string>
              </dict>
            </array>
          </dict>
        </array>
      </dict>
      </plist>
      """

      stub(Tuist.IngestRepo, :one, fn _query -> session end)

      stub(Tuist.Storage, :multipart_complete_upload, fn _key, _upload_id, _parts, _account ->
        :ok
      end)

      stub(Tuist.Storage, :get_object_as_string, fn _key, _account -> sample_xctestrun end)

      put_object_count = :counters.new(1, [])

      stub(Tuist.Storage, :put_object, fn _key, _content, _account ->
        :counters.add(put_object_count, 1, 1)
        :ok
      end)

      stub(Tuist.IngestRepo, :insert_all, fn _schema, _data -> {1, nil} end)

      assert {:ok, _session} =
               Shards.complete_upload(project, account, "session-1", "upload-id", [])

      assert :counters.get(put_object_count, 1) == 2
    end

    test "returns error for nonexistent session" do
      project = ProjectsFixtures.project_fixture()
      account = project.account

      stub(Tuist.IngestRepo, :one, fn _query -> nil end)

      assert {:error, :not_found} =
               Shards.complete_upload(project, account, "nonexistent", "upload-id", [])
    end
  end
end
