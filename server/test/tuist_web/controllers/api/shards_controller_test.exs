defmodule TuistWeb.API.ShardsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

    stub(Tuist.IngestRepo, :all, fn _query -> [] end)
    stub(Tuist.IngestRepo, :insert, fn changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)} end)
    stub(Tuist.IngestRepo, :one, fn _query -> nil end)
    stub(Tuist.IngestRepo, :insert_all, fn _schema, _data -> {1, nil} end)
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
      stub(Tuist.Shards, :get_shard, fn _project, _account, _plan_id, _shard_index ->
        {:ok, %{test_targets: ["AppTests"], bundle_download_url: "https://download.example.com"}}
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/session-1/0")

      response = json_response(conn, :ok)
      assert response["test_targets"] == ["AppTests"]
      assert response["bundle_download_url"] == "https://download.example.com"
    end

    test "returns not found for nonexistent session", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :get_shard, fn _project, _account, _plan_id, _shard_index ->
        {:error, :not_found}
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/nonexistent/0")

      response = json_response(conn, :not_found)
      assert response["message"] =~ "not found"
    end

    test "returns not found for out-of-range shard index", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :get_shard, fn _project, _account, _plan_id, _shard_index ->
        {:error, :invalid_shard_index}
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/session-1/99")

      response = json_response(conn, :not_found)
      assert response["message"] =~ "out of range"
    end
  end

  describe "POST /api/projects/:account/:project/tests/shards/generate-url" do
    test "returns signed upload URL", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :generate_upload_url, fn _project, _account, _plan_id, _upload_id, _part ->
        {:ok, "https://upload.example.com/part"}
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
  end

  describe "POST /api/projects/:account/:project/tests/shards/complete" do
    test "completes upload successfully", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :complete_upload, fn _project, _account, _plan_id, _upload_id, _parts ->
        :ok
      end)

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
      stub(Tuist.Shards, :complete_upload, fn _project, _account, _plan_id, _upload_id, _parts ->
        {:error, :not_found}
      end)

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
