defmodule TuistWeb.API.BundleArtifactsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Bundles
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/bundles/:bundle_id/artifacts" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns the artifact tree for a bundle", %{conn: conn, user: user, project: project} do
      # Given
      bundle_id = UUIDv7.generate()

      stub(Bundles, :get_bundle, fn id ->
        assert id == bundle_id
        {:ok, %{project_id: project.id}}
      end)

      stub(Bundles, :get_bundle_artifact_tree, fn id ->
        assert id == bundle_id

        [
          %{artifact_type: "framework", path: "App.framework", size: 2048},
          %{artifact_type: "resource", path: "Assets.car", size: 512}
        ]
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/bundles/#{bundle_id}/artifacts"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["bundle_id"] == bundle_id
      assert length(response["artifacts"]) == 2

      first = hd(response["artifacts"])
      assert first["artifact_type"] == "framework"
      assert first["path"] == "App.framework"
      assert first["size"] == 2048
    end

    test "returns empty artifact list when bundle has no artifacts", %{conn: conn, user: user, project: project} do
      # Given
      bundle_id = UUIDv7.generate()

      stub(Bundles, :get_bundle, fn _id ->
        {:ok, %{project_id: project.id}}
      end)

      stub(Bundles, :get_bundle_artifact_tree, fn _id ->
        []
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/bundles/#{bundle_id}/artifacts"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["bundle_id"] == bundle_id
      assert response["artifacts"] == []
    end

    test "returns 404 when bundle does not exist", %{conn: conn, user: user, project: project} do
      # Given
      bundle_id = UUIDv7.generate()

      stub(Bundles, :get_bundle, fn _id ->
        {:error, :not_found}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/bundles/#{bundle_id}/artifacts"
        )

      # Then
      assert %{"message" => "Bundle not found."} = json_response(conn, :not_found)
    end

    test "returns 404 when bundle belongs to a different project", %{conn: conn, user: user, project: project} do
      # Given
      bundle_id = UUIDv7.generate()
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      stub(Bundles, :get_bundle, fn _id ->
        {:ok, %{project_id: other_project.id}}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/bundles/#{bundle_id}/artifacts"
        )

      # Then
      assert %{"message" => "Bundle not found."} = json_response(conn, :not_found)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/bundles/#{UUIDv7.generate()}/artifacts"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
