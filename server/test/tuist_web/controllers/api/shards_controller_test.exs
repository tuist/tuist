defmodule TuistWeb.API.ShardsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Shards.ShardPlan
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

    stub(Tuist.IngestRepo, :all, fn _query -> [] end)
    stub(Tuist.IngestRepo, :insert, fn changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)} end)
    stub(Tuist.IngestRepo, :one, fn _query -> nil end)
    stub(Tuist.Storage, :multipart_start, fn _key, _account -> "upload-id-123" end)

    %{user: user, project: project}
  end

  describe "POST /api/projects/:account/:project/tests/shards" do
    test "creates shard plan with valid params", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards",
          %{
            plan_id: "github-123-1",
            modules: ["AppTests", "CoreTests"],
            shard_max: 2
          }
        )

      response = json_response(conn, :ok)
      assert response["plan_id"] == "github-123-1"
      assert response["shard_count"] == 2
      assert is_list(response["shards"])
      assert response["upload_id"] == "upload-id-123"
    end

    test "returns forbidden when user doesn't have access", %{conn: conn} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      other_project = ProjectsFixtures.project_fixture(preload: [:account], account_id: other_user.account.id)

      conn =
        conn
        |> Authentication.put_current_user(AccountsFixtures.user_fixture(preload: [:account]))
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{other_project.account.name}/#{other_project.name}/tests/shards",
          %{
            plan_id: "session-1",
            modules: ["AppTests"]
          }
        )

      assert response(conn, :forbidden)
    end

    test "returns unauthorized when not authenticated", %{conn: conn, project: project} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards",
          %{
            plan_id: "session-1",
            modules: ["AppTests"]
          }
        )

      assert response(conn, :unauthorized)
    end
  end

  describe "GET /api/projects/:account/:project/tests/shards/:plan_id/:shard_index" do
    test "returns shard assignment for valid params", %{conn: conn, user: user, project: project} do
      session = %ShardPlan{
        id: Ecto.UUID.generate(),
        plan_id: "session-1",
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
      stub(Tuist.Storage, :generate_download_url, fn _key, _account -> "https://download.example.com" end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/session-1/0")

      response = json_response(conn, :ok)
      assert response["test_targets"] == ["AppTests"]
      assert response["xctestrun_download_url"] == "https://download.example.com"
      assert response["bundle_download_url"] == "https://download.example.com"
    end

    test "returns not found for nonexistent session", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/nonexistent/0")

      response = json_response(conn, :not_found)
      assert response["message"] =~ "not found"
    end

    test "returns not found for out-of-range shard index", %{conn: conn, user: user, project: project} do
      session = %ShardPlan{
        id: Ecto.UUID.generate(),
        plan_id: "session-1",
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

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/session-1/99")

      response = json_response(conn, :not_found)
      assert response["message"] =~ "out of range"
    end
  end

  describe "POST /api/projects/:account/:project/tests/shards/generate-url" do
    test "returns signed upload URL for existing session", %{conn: conn, user: user, project: project} do
      session = %ShardPlan{
        id: Ecto.UUID.generate(),
        plan_id: "session-1",
        project_id: project.id,
        shard_count: 2,
        granularity: "module",
        shard_assignments:
          Jason.encode!([%{"index" => 0, "test_targets" => ["AppTests"], "estimated_duration_ms" => 100}]),
        bundle_object_key: "bundle.zip",
        xctestrun_object_key: "original.xctestrun",
        upload_completed: 0,
        inserted_at: NaiveDateTime.utc_now()
      }

      stub(Tuist.IngestRepo, :one, fn _query -> session end)

      stub(Tuist.Storage, :multipart_generate_url, fn _key, _upload_id, _part, _account ->
        "https://upload.example.com/part"
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/generate-url",
          %{plan_id: "session-1", upload_id: "upload-id", part_number: 1}
        )

      response = json_response(conn, :ok)
      assert response["data"]["url"] == "https://upload.example.com/part"
    end

    test "returns not found for nonexistent session", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/generate-url",
          %{plan_id: "nonexistent", upload_id: "upload-id", part_number: 1}
        )

      response = json_response(conn, :not_found)
      assert response["message"] =~ "not found"
    end
  end

  describe "POST /api/projects/:account/:project/tests/shards/generate-xctestrun-url" do
    test "returns signed upload URL for existing session", %{conn: conn, user: user, project: project} do
      session = %ShardPlan{
        id: Ecto.UUID.generate(),
        plan_id: "session-1",
        project_id: project.id,
        shard_count: 2,
        granularity: "module",
        shard_assignments:
          Jason.encode!([%{"index" => 0, "test_targets" => ["AppTests"], "estimated_duration_ms" => 100}]),
        bundle_object_key: "bundle.zip",
        xctestrun_object_key: "original.xctestrun",
        upload_completed: 0,
        inserted_at: NaiveDateTime.utc_now()
      }

      stub(Tuist.IngestRepo, :one, fn _query -> session end)
      stub(Tuist.Storage, :generate_upload_url, fn _key, _account -> "https://upload.example.com/xctestrun" end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/generate-xctestrun-url",
          %{plan_id: "session-1"}
        )

      response = json_response(conn, :ok)
      assert response["data"]["url"] == "https://upload.example.com/xctestrun"
    end

    test "returns not found for nonexistent session", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/generate-xctestrun-url",
          %{plan_id: "nonexistent"}
        )

      response = json_response(conn, :not_found)
      assert response["message"] =~ "not found"
    end
  end

  describe "POST /api/projects/:account/:project/tests/shards/complete" do
    test "completes upload successfully", %{conn: conn, user: user, project: project} do
      session = %ShardPlan{
        id: Ecto.UUID.generate(),
        plan_id: "session-1",
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
      stub(Tuist.Storage, :multipart_complete_upload, fn _key, _upload_id, _parts, _account -> :ok end)
      stub(Tuist.Storage, :get_object_as_string, fn _key, _account -> sample_xctestrun end)
      stub(Tuist.Storage, :put_object, fn _key, _content, _account -> :ok end)
      stub(Tuist.IngestRepo, :insert_all, fn _schema, _data -> {1, nil} end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/complete",
          %{plan_id: "session-1", upload_id: "upload-id", parts: [%{part_number: 1, etag: "etag1"}]}
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
    end

    test "returns not found for nonexistent session", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/complete",
          %{plan_id: "nonexistent", upload_id: "upload-id", parts: []}
        )

      response = json_response(conn, :not_found)
      assert response["message"] =~ "not found"
    end
  end
end
