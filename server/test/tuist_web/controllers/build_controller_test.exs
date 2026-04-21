defmodule TuistWeb.BuildControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Builds
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :verify_on_exit!

  describe "download/2" do
    test "redirects to the presigned URL when user has permission",
         %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      build_id = UUIDv7.generate()

      stub(Builds, :get_build, fn ^build_id ->
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

      stub(Builds, :get_build, fn ^build_id -> {:error, :not_found} end)

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

      stub(Builds, :get_build, fn ^build_id ->
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
