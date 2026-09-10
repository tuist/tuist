defmodule TuistWeb.BuildControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Builds
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup :verify_on_exit!

  describe "timeline/2" do
    test "returns full metadata and distinct project/target counts without logs", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      steps =
        for {id, target, xcode_project} <- [
              {1, "App", "Workspace"},
              {2, "App", "Workspace"},
              {3, "App", "Other"},
              {4, "", "Workspace"}
            ] do
          %{
            event_id: id,
            title: "Compile",
            target: target,
            project: xcode_project,
            start_ms: id * 100.0,
            duration_ms: 10.0,
            status: "success",
            log: "Private log"
          }
        end

      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, build_steps: steps)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{build.id}/timeline.json")

      response = json_response(conn, 200)
      assert response["total_count"] == 4
      assert response["target_count"] == 2
      assert length(response["events"]) == 4
      refute Map.has_key?(hd(response["events"]), "log")
      refute Map.has_key?(response, "machine_metrics")
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "does not allow access through another project or user", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, other_build} = RunsFixtures.build_fixture()
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
      reject(Builds, :build_timeline, 2)

      assert_error_sent 404, fn ->
        conn
        |> log_in_user(user)
        |> get(~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{other_build.id}/timeline.json")
      end

      stranger = AccountsFixtures.user_fixture()

      assert_error_sent 404, fn ->
        conn
        |> log_in_user(stranger)
        |> get(~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{build.id}/timeline.json")
      end
    end

    test "allows anonymous access to a public build", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(visibility: :public)
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
      conn = get(conn, ~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{build.id}/timeline.json")
      assert %{"total_count" => 0} = json_response(conn, 200)
    end

    test "does not disguise a metadata query failure as an empty timeline", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
      expect(Builds, :build_timeline, fn _, _ -> raise "database unavailable" end)

      assert_error_sent 500, fn ->
        conn
        |> log_in_user(user)
        |> get(~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{build.id}/timeline.json")
      end
    end

    test "returns an empty payload for a build without recorded steps", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)

      response =
        conn
        |> log_in_user(user)
        |> get(~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{build.id}/timeline.json")
        |> json_response(200)

      assert %{"events" => [], "total_count" => 0, "target_count" => 0} = response
    end
  end

  describe "download/2" do
    test "redirects to the presigned URL when user has permission",
         %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      build_id = UUIDv7.generate()

      stub(Builds, :get_build, fn ^build_id, _opts ->
        {:ok,
         %Builds.Build{
           id: build_id,
           project_id: project.id
         }}
      end)

      stub(Storage, :generate_download_url, fn _storage_key, _account ->
        "https://storage.example.com/presigned-url"
      end)

      # When
      conn =
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{build_id}/download"
        )

      # Then
      assert redirected_to(conn) == "https://storage.example.com/presigned-url"
    end

    test "returns 404 when build does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      build_id = UUIDv7.generate()

      stub(Builds, :get_build, fn ^build_id, _opts -> {:error, :not_found} end)

      # When/Then
      assert_error_sent 404, fn ->
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{build_id}/download"
        )
      end
    end

    test "returns 404 when user does not have permission", %{conn: conn} do
      # Given
      owner = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account_id: owner.account.id)
      build_id = UUIDv7.generate()
      conn = log_in_user(conn, other_user)

      # When
      # The require_user_can_read_project plug returns 404 for security reasons
      # (to not reveal existence of projects users don't have access to)
      assert_error_sent 404, fn ->
        get(
          conn,
          ~p"/#{owner.account.name}/#{project.name}/builds/build-runs/#{build_id}/download"
        )
      end
    end

    test "returns 404 when build belongs to different project", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      build_id = UUIDv7.generate()

      stub(Builds, :get_build, fn ^build_id, _opts ->
        {:ok,
         %Builds.Build{
           id: build_id,
           project_id: other_project.id
         }}
      end)

      # When/Then
      assert_error_sent 404, fn ->
        get(
          conn,
          ~p"/#{user.account.name}/#{project.name}/builds/build-runs/#{build_id}/download"
        )
      end
    end
  end
end
