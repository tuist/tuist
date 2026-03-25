defmodule TuistWeb.API.ShardsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(preload: [:account], account_id: user.account.id)

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
            reference: "github-123-1",
            modules: ["AppTests", "CoreTests"],
            shard_max: 2
          }
        )

      response = json_response(conn, :ok)
      assert response["reference"] == "github-123-1"
      assert response["shard_count"] == 2
      assert is_list(response["shards"])
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
            reference: "session-1",
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
            reference: "session-1",
            modules: ["AppTests"]
          }
        )

      assert response(conn, :unauthorized)
    end

    test "returns bad request when reference is missing", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards",
          %{
            modules: ["AppTests"]
          }
        )

      assert response(conn, 400)
    end

    test "creates plan with empty modules list", %{conn: conn, user: user, project: project} do
      plan_id = Ecto.UUID.generate()

      stub(Tuist.Shards, :create_shard_plan, fn _project, _params ->
        %{
          plan: %{id: plan_id, reference: "empty-modules-ref"},
          shard_count: 1,
          shard_assignments: [%{"index" => 0, "test_targets" => [], "estimated_duration_ms" => 0}]
        }
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards",
          %{
            reference: "empty-modules-ref",
            modules: []
          }
        )

      response = json_response(conn, :ok)
      assert response["reference"] == "empty-modules-ref"
      assert is_integer(response["shard_count"])
    end

    test "accepts and stores build_run_id parameter", %{conn: conn, user: user, project: project} do
      build_run_id = Ecto.UUID.generate()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards",
          %{
            reference: "build-id-ref",
            modules: ["AppTests"],
            build_run_id: build_run_id
          }
        )

      response = json_response(conn, :ok)
      {:ok, plan} = Tuist.Shards.get_shard_plan(response["id"])
      assert plan.build_run_id == build_run_id
    end

    test "accepts and stores gradle_build_id parameter", %{conn: conn, user: user, project: project} do
      gradle_build_id = Ecto.UUID.generate()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards",
          %{
            reference: "gradle-id-ref",
            modules: ["AppTests"],
            gradle_build_id: gradle_build_id
          }
        )

      response = json_response(conn, :ok)
      {:ok, plan} = Tuist.Shards.get_shard_plan(response["id"])
      assert plan.gradle_build_id == gradle_build_id
    end

    test "response includes id field", %{conn: conn, user: user, project: project} do
      plan_id = Ecto.UUID.generate()

      stub(Tuist.Shards, :create_shard_plan, fn _project, _params ->
        %{
          plan: %{id: plan_id, reference: "id-check-ref"},
          shard_count: 2,
          shard_assignments: [
            %{"index" => 0, "test_targets" => ["AppTests"], "estimated_duration_ms" => 1000},
            %{"index" => 1, "test_targets" => [], "estimated_duration_ms" => 0}
          ]
        }
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards",
          %{
            reference: "id-check-ref",
            modules: ["AppTests"]
          }
        )

      response = json_response(conn, :ok)
      assert is_binary(response["id"])
      assert {:ok, _} = Ecto.UUID.cast(response["id"])
    end
  end

  describe "GET /api/projects/:account/:project/tests/shards/:reference/:shard_index" do
    test "returns shard for valid params", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :get_shard, fn _project, _account, _reference, _shard_index ->
        {:ok,
         %{
           shard_plan_id: Ecto.UUID.generate(),
           modules: ["AppTests"],
           suites: %{},
           download_url: "https://download.example.com"
         }}
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/session-1/0")

      response = json_response(conn, :ok)
      assert response["modules"] == ["AppTests"]
      assert response["suites"] == %{}
      assert response["download_url"] == "https://download.example.com"
    end

    test "returns not found for nonexistent plan", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :get_shard, fn _project, _account, _reference, _shard_index ->
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
      stub(Tuist.Shards, :get_shard, fn _project, _account, _reference, _shard_index ->
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

  describe "POST /api/projects/:account/:project/tests/shards/upload/generate-url" do
    test "returns signed upload URL", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :generate_upload_url, fn _project, _account, _reference, _upload_id, _part ->
        {:ok, "https://upload.example.com/part"}
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/upload/generate-url",
          %{reference: "session-1", upload_id: "upload-id", part_number: 1}
        )

      response = json_response(conn, :ok)
      assert response["data"]["url"] == "https://upload.example.com/part"
    end
  end

  describe "POST /api/projects/:account/:project/tests/shards/upload/complete" do
    test "completes upload successfully", %{conn: conn, user: user, project: project} do
      stub(Tuist.Shards, :complete_upload, fn _project, _account, _reference, _upload_id, _parts ->
        :ok
      end)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{project.account.name}/#{project.name}/tests/shards/upload/complete",
          %{reference: "session-1", upload_id: "upload-id", parts: [%{part_number: 1, etag: "etag1"}]}
        )

      response = json_response(conn, :ok)
      assert response["status"] == "success"
    end
  end
end
