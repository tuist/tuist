defmodule TuistWeb.API.CASControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    %{
      user: user,
      project: project,
      account_handle: user.account.name,
      project_handle: project.name
    }
  end

  describe "GET /api/cache/cas/:id" do
    test "loads CAS artifact successfully", %{
      conn: conn,
      project: project,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_project(conn, project)

      cas_id = "0~YWoYNXX123"
      expected_key = "#{account_handle}/#{project_handle}/cas/#{cas_id}"
      artifact_content = "mock artifact content"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        true
      end)

      expect(Storage, :stream_object, fn key, _current_subject ->
        assert key == expected_key
        [artifact_content]
      end)

      # When
      conn = get(conn, ~p"/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      # Then
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/octet-stream; charset=utf-8"]
    end

    test "returns not found when artifact doesn't exist", %{
      conn: conn,
      project: project,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_project(conn, project)

      cas_id = "0~nonexistent123"
      expected_key = "#{account_handle}/#{project_handle}/cas/#{cas_id}"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        false
      end)

      # When
      conn = get(conn, ~p"/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      # Then
      assert conn.status == 404
    end

    test "returns not found when account doesn't exist", %{
      conn: conn,
      user: user,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      cas_id = "0~YWoYNXX123"

      # When
      conn =
        get(conn, ~p"/api/cache/cas/#{cas_id}?account_handle=nonexistent-account&project_handle=#{project_handle}")

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns not found when project doesn't exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      cas_id = "0~YWoYNXX123"

      # When
      conn =
        get(conn, ~p"/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=nonexistent-project")

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns forbidden when user doesn't have permission", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      cas_id = "0~YWoYNXX123"

      # When
      conn =
        get(
          conn,
          ~p"/api/cache/cas/#{cas_id}?account_handle=#{other_project.account.name}&project_handle=#{other_project.name}"
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end

  describe "POST /api/cache/cas/:id" do
    test "uploads CAS artifact successfully", %{
      conn: conn,
      project: project,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_project(conn, project)

      cas_id = "0~YWoYNXX123"
      expected_key = "#{project.account.name}/#{project.name}/cas/#{cas_id}"
      artifact_content = "new artifact content"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        false
      end)

      expect(Storage, :put_object, fn key, body, _current_subject ->
        assert key == expected_key
        assert body == artifact_content
        :ok
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          ~p"/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          artifact_content
        )

      # Then
      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns ok when artifact already exists", %{
      conn: conn,
      project: project,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_project(conn, project)

      cas_id = "0~YWoYNXX123"
      expected_key = "#{project.account.name}/#{project.name}/cas/#{cas_id}"
      artifact_content = "existing artifact content"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        true
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          ~p"/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}",
          artifact_content
        )

      # Then
      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns not found when account doesn't exist", %{
      conn: conn,
      user: user,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      cas_id = "0~YWoYNXX123"
      artifact_content = "artifact content"

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          ~p"/api/cache/cas/#{cas_id}?account_handle=nonexistent-account&project_handle=#{project_handle}",
          artifact_content
        )

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns not found when project doesn't exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      cas_id = "0~YWoYNXX123"
      artifact_content = "artifact content"

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          ~p"/api/cache/cas/#{cas_id}?account_handle=#{account_handle}&project_handle=nonexistent-project",
          artifact_content
        )

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns forbidden when user doesn't have permission", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      cas_id = "0~YWoYNXX123"
      artifact_content = "artifact content"

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(
          ~p"/api/cache/cas/#{cas_id}?account_handle=#{other_project.account.name}&project_handle=#{other_project.name}",
          artifact_content
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end
end
