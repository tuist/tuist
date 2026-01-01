defmodule TuistWeb.API.Cache.GradleControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup do
    organization = AccountsFixtures.organization_fixture()
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

    # Create an account token with cache permissions
    {:ok, {account_token, token}} =
      Accounts.create_account_token(%{
        account: organization.account,
        name: "test-gradle-token",
        scopes: ["project:cache:read", "project:cache:write"],
        all_projects: true
      })

    %{
      organization: organization,
      project: project,
      account_token: account_token,
      token: token,
      account_handle: organization.account.name,
      project_handle: project.name
    }
  end

  defp basic_auth_header(token) do
    credentials = Base.encode64("token:#{token}")
    {"authorization", "Basic #{credentials}"}
  end

  describe "GET /api/cache/gradle/:account_handle/:project_handle/:hash (load)" do
    test "loads artifact successfully with valid token", %{
      conn: conn,
      token: token,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      hash = "abc123def456"
      expected_key = "#{account_handle}/#{project_handle}/gradle/#{hash}"
      artifact_content = "gradle cache artifact"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        true
      end)

      expect(Storage, :stream_object, fn key, _current_subject ->
        assert key == expected_key
        [artifact_content]
      end)

      conn =
        conn
        |> put_req_header("authorization", elem(basic_auth_header(token), 1))
        |> get("/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/octet-stream; charset=utf-8"]
    end

    test "returns 404 when artifact doesn't exist", %{
      conn: conn,
      token: token,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      hash = "nonexistent123"
      expected_key = "#{account_handle}/#{project_handle}/gradle/#{hash}"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        false
      end)

      conn =
        conn
        |> put_req_header("authorization", elem(basic_auth_header(token), 1))
        |> get("/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}")

      assert conn.status == 404
    end

    test "returns 401 without authentication", %{
      conn: conn,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      hash = "abc123def456"

      conn = get(conn, "/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}")

      assert conn.status == 401
    end

    test "returns 401 with invalid token", %{
      conn: conn,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      hash = "abc123def456"

      conn =
        conn
        |> put_req_header("authorization", elem(basic_auth_header("invalid_token"), 1))
        |> get("/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}")

      assert conn.status == 401
    end
  end

  describe "PUT /api/cache/gradle/:account_handle/:project_handle/:hash (save)" do
    test "saves artifact successfully", %{
      conn: conn,
      token: token,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      hash = "abc123def456"
      expected_key = "#{account_handle}/#{project_handle}/gradle/#{hash}"
      artifact_content = "gradle cache artifact data"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        false
      end)

      expect(Storage, :put_object, fn key, body, _current_subject ->
        assert key == expected_key
        assert body == artifact_content
        :ok
      end)

      conn =
        conn
        |> put_req_header("authorization", elem(basic_auth_header(token), 1))
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}", artifact_content)

      assert conn.status == 200
    end

    test "skips upload when artifact already exists", %{
      conn: conn,
      token: token,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      hash = "existing123"
      expected_key = "#{account_handle}/#{project_handle}/gradle/#{hash}"
      artifact_content = "gradle cache artifact data"

      expect(Storage, :object_exists?, fn key, _current_subject ->
        assert key == expected_key
        true
      end)

      # put_object should NOT be called since artifact exists
      reject(&Storage.put_object/3)

      conn =
        conn
        |> put_req_header("authorization", elem(basic_auth_header(token), 1))
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}", artifact_content)

      assert conn.status == 200
    end

    test "returns 401 without authentication", %{
      conn: conn,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      hash = "abc123def456"
      artifact_content = "gradle cache artifact data"

      conn =
        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> put("/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}", artifact_content)

      assert conn.status == 401
    end
  end

  describe "access control" do
    test "returns 403 when token doesn't have cache scope", %{
      conn: conn,
      organization: organization,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Create a token without cache scopes
      {:ok, {_account_token, token}} =
        Accounts.create_account_token(%{
          account: organization.account,
          name: "no-cache-token",
          scopes: ["project:previews:read"],
          all_projects: true
        })

      hash = "abc123def456"

      conn =
        conn
        |> put_req_header("authorization", elem(basic_auth_header(token), 1))
        |> get("/api/cache/gradle/#{account_handle}/#{project_handle}/#{hash}")

      assert conn.status == 403
      assert json_response(conn, 403)["message"] =~ "not authorized"
    end

    test "returns 404 when project doesn't exist", %{
      conn: conn,
      token: token,
      account_handle: account_handle
    } do
      hash = "abc123def456"

      assert_raise NotFoundError, fn ->
        conn
        |> put_req_header("authorization", elem(basic_auth_header(token), 1))
        |> get("/api/cache/gradle/#{account_handle}/nonexistent-project/#{hash}")
      end
    end

    test "returns 404 when token belongs to different account", %{
      conn: conn,
      project_handle: project_handle
    } do
      # Create a different organization with its own token
      other_org = AccountsFixtures.organization_fixture()

      {:ok, {_account_token, other_token}} =
        Accounts.create_account_token(%{
          account: other_org.account,
          name: "other-org-token",
          scopes: ["project:cache:read", "project:cache:write"],
          all_projects: true
        })

      hash = "abc123def456"

      # Raises NotFoundError because project doesn't exist under other org's account
      assert_raise NotFoundError, fn ->
        conn
        |> put_req_header("authorization", elem(basic_auth_header(other_token), 1))
        |> get("/api/cache/gradle/#{other_org.account.name}/#{project_handle}/#{hash}")
      end
    end
  end
end
