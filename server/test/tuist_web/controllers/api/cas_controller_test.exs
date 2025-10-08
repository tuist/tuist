defmodule TuistWeb.API.CASControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io", preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, name: "test-project")
    %{user: user, project: project}
  end

  describe "GET /api/cas/prefix" do
    test "returns the CAS prefix for an authenticated user with access to the project", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/prefix?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      response = json_response(conn, :ok)

      assert %{"prefix" => prefix} = response
      assert prefix == "#{user.account.id}/#{project.id}/xcode/cas/"
    end

    test "returns the CAS prefix for an authenticated project token", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      full_token = Projects.create_project_token(project)

      conn = put_req_header(conn, "authorization", "Bearer #{full_token}")

      # When
      conn = get(conn, ~p"/api/cas/prefix?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      response = json_response(conn, :ok)

      assert %{"prefix" => prefix} = response
      assert prefix == "#{user.account.id}/#{project.id}/xcode/cas/"
    end

    test "returns 401 when not authenticated", %{
      conn: conn,
      user: user,
      project: project
    } do
      # When
      conn = get(conn, ~p"/api/cas/prefix?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      response = json_response(conn, :unauthorized)

      assert %{"message" => "You need to be authenticated to access this resource."} = response
    end

    test "returns 404 when account does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/prefix?account_handle=non-existent-account&project_handle=#{project.name}")

      # Then
      response = json_response(conn, :not_found)

      assert %{"message" => "Account non-existent-account not found."} = response
    end

    test "returns 404 when project does not exist", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/prefix?account_handle=#{user.account.name}&project_handle=non-existent-project")

      # Then
      response = json_response(conn, :not_found)

      assert %{"message" => message} = response
      assert message =~ "Project #{user.account.name}/non-existent-project not found."
    end

    test "returns 403 when user does not have access to the project", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id, name: "other-project")
      user = AccountsFixtures.user_fixture(email: "noauth@tuist.io", preload: [:account])

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/prefix?account_handle=#{other_user.account.name}&project_handle=#{other_project.name}")

      # Then
      response = json_response(conn, :forbidden)

      assert %{"message" => message} = response
      assert message =~ "You don't have permission to access the #{other_project.name} project."
    end

    test "returns the CAS prefix for an organization member with access", %{
      conn: conn,
      user: user
    } do
      # Given
      {:ok, organization} = Accounts.create_organization(%{name: "test-org", creator: user})
      Accounts.add_user_to_organization(user, organization)

      org_project = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "org-project")

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/prefix?account_handle=#{organization.account.name}&project_handle=#{org_project.name}")

      # Then
      response = json_response(conn, :ok)

      assert %{"prefix" => prefix} = response
      assert prefix == "#{organization.account.id}/#{org_project.id}/xcode/cas/"
    end
  end

  describe "GET /api/cas/:id" do
    test "redirects to presigned S3 URL when artifact exists", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)
      artifact_id = "abc123"
      presigned_url = "https://s3.amazonaws.com/bucket/object?signed=true"

      expect(Storage, :object_exists?, fn _key, _actor -> true end)
      expect(Storage, :generate_download_url, fn _key, _actor -> presigned_url end)

      # When
      conn = get(conn, ~p"/api/cas/#{artifact_id}?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      assert redirected_to(conn, 302) == presigned_url
    end

    test "returns 404 when artifact does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)
      artifact_id = "abc123"

      expect(Storage, :object_exists?, fn _key, _actor -> false end)

      # When
      conn = get(conn, ~p"/api/cas/#{artifact_id}?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      assert conn.status == 404
      assert conn.resp_body == ""
    end

    test "returns 401 when not authenticated", %{
      conn: conn,
      user: user,
      project: project
    } do
      # When
      conn = get(conn, ~p"/api/cas/abc123?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      response = json_response(conn, :unauthorized)

      assert %{"message" => "You need to be authenticated to access this resource."} = response
    end

    test "returns 404 when account does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/abc123?account_handle=non-existent-account&project_handle=#{project.name}")

      # Then
      assert conn.status == 404
      assert conn.resp_body == ""
    end

    test "returns 404 when project does not exist", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/abc123?account_handle=#{user.account.name}&project_handle=non-existent-project")

      # Then
      assert conn.status == 404
      assert conn.resp_body == ""
    end

    test "returns 403 when user does not have access to the project", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id, name: "other-project")
      user = AccountsFixtures.user_fixture(email: "noauth@tuist.io", preload: [:account])

      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, ~p"/api/cas/abc123?account_handle=#{other_user.account.name}&project_handle=#{other_project.name}")

      # Then
      response = json_response(conn, :forbidden)

      assert %{"message" => message} = response
      assert message =~ "You don't have permission to access the #{other_project.name} project."
    end
  end

  describe "POST /api/cas/:id" do
    test "redirects to presigned upload URL when artifact does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)
      artifact_id = "abc123"
      presigned_url = "https://s3.amazonaws.com/bucket/upload?signed=true"

      expect(Storage, :object_exists?, fn _key, _actor -> false end)
      expect(Storage, :generate_upload_url, fn _key, _actor -> presigned_url end)

      # When
      conn = post(conn, ~p"/api/cas/#{artifact_id}?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      assert redirected_to(conn, 302) == presigned_url
    end

    test "returns 304 when artifact already exists", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)
      artifact_id = "abc123"

      expect(Storage, :object_exists?, fn _key, _actor -> true end)

      # When
      conn = post(conn, ~p"/api/cas/#{artifact_id}?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      assert conn.status == 304
      assert conn.resp_body == ""
    end

    test "returns 401 when not authenticated", %{
      conn: conn,
      user: user,
      project: project
    } do
      # When
      conn = post(conn, ~p"/api/cas/abc123?account_handle=#{user.account.name}&project_handle=#{project.name}")

      # Then
      response = json_response(conn, :unauthorized)

      assert %{"message" => "You need to be authenticated to access this resource."} = response
    end

    test "returns 404 when account does not exist", %{
      conn: conn,
      user: user,
      project: project
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = post(conn, ~p"/api/cas/abc123?account_handle=non-existent-account&project_handle=#{project.name}")

      # Then
      assert conn.status == 404
      assert conn.resp_body == ""
    end

    test "returns 404 when project does not exist", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = post(conn, ~p"/api/cas/abc123?account_handle=#{user.account.name}&project_handle=non-existent-project")

      # Then
      assert conn.status == 404
      assert conn.resp_body == ""
    end

    test "returns 403 when user does not have write access to the project", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id, name: "other-project")
      user = AccountsFixtures.user_fixture(email: "noauth@tuist.io", preload: [:account])

      conn = Authentication.put_current_user(conn, user)

      # When
      conn =
        post(conn, ~p"/api/cas/abc123?account_handle=#{other_user.account.name}&project_handle=#{other_project.name}")

      # Then
      response = json_response(conn, :forbidden)

      assert %{"message" => message} = response
      assert message =~ "You don't have permission to write to the #{other_project.name} project."
    end
  end
end
