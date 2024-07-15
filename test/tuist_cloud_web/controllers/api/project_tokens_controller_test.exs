defmodule TuistCloudWeb.API.ProjectTokensControllerTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic
  alias TuistCloud.Projects
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures

  describe "POST /projects/:account_name/:project_name/tokens" do
    test "returns new project access token", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      project =
        ProjectsFixtures.project_fixture(
          account_id: organization.account.id,
          preloads: [:account]
        )

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      Projects
      |> expect(:create_project_token, fn ^project -> "project_access_token" end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/#{project.account.name}/#{project.name}/tokens")

      # Then
      response = json_response(conn, :ok)
      assert response["token"] == "project_access_token"
    end

    test "returns not_found when a project does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/tuist/tuist-project/tokens")

      # Then
      response = json_response(conn, :not_found)
      assert response == %{"message" => "The project tuist/tuist-project was not found"}
    end

    test "returns forbidden when a user can't create a new project access token", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(preloads: [:account])

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/projects/#{project.account.name}/#{project.name}/tokens")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "The authenticated subject is not authorized to perform this action"
             }
    end
  end

  describe "GET /projects/:account_name/:project_name/tokens" do
    test "returns all project tokens", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      project =
        ProjectsFixtures.project_fixture(
          account_id: organization.account.id,
          preloads: [:account]
        )

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      token_one = Projects.create_project_token(project)
      token_two = Projects.create_project_token(project)
      _token_three = Projects.create_project_token(ProjectsFixtures.project_fixture())

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/api/projects/#{project.account.name}/#{project.name}/tokens")

      # Then
      response = json_response(conn, :ok)
      {:ok, token_one} = Projects.get_project_token(token_one)
      {:ok, token_two} = Projects.get_project_token(token_two)

      assert [
               %{
                 "id" => token_one.id,
                 "inserted_at" =>
                   token_one.inserted_at
                   |> DateTime.to_iso8601()
               },
               %{
                 "id" => token_two.id,
                 "inserted_at" => token_two.inserted_at |> DateTime.to_iso8601()
               }
             ]
             |> Enum.sort_by(& &1["id"]) == response["tokens"] |> Enum.sort_by(& &1["id"])
    end

    test "returns empty array if there are no project tokens", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      project =
        ProjectsFixtures.project_fixture(
          account_id: organization.account.id,
          preloads: [:account]
        )

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/api/projects/#{project.account.name}/#{project.name}/tokens")

      # Then
      response = json_response(conn, :ok)
      assert [] == response["tokens"]
    end

    test "returns forbidden when a user can't read project tokens", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(preloads: [:account])

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/api/projects/#{project.account.name}/#{project.name}/tokens")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "The authenticated subject is not authorized to perform this action"
             }
    end

    test "returns not_found when the project does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/api/projects/tuist/tuist-project/tokens")

      # Then
      response = json_response(conn, :not_found)
      assert response == %{"message" => "The project tuist/tuist-project was not found"}
    end
  end

  describe "DELETE /projects/:account_name/:project_name/tokens/:id" do
    test "revokes a project token", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      project =
        ProjectsFixtures.project_fixture(
          account_id: organization.account.id,
          preloads: [:account]
        )

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      full_token = Projects.create_project_token(project)

      {:ok, token} =
        Projects.get_project_token(full_token)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/projects/#{project.account.name}/#{project.name}/tokens/#{token.id}")

      # Then
      response = json_response(conn, :no_content)
      assert response == %{}
      assert Projects.get_project_tokens(project) |> Enum.empty?() == true
    end

    test "returns forbidden when a user can't revoke a project token", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(preloads: [:account])

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      full_token = Projects.create_project_token(project)

      token =
        Projects.get_project_tokens(project)
        |> hd()

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/projects/#{project.account.name}/#{project.name}/tokens/#{token.id}")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "The authenticated subject is not authorized to perform this action"
             }

      assert Projects.get_project_token(full_token) == {:ok, token}
    end

    test "returns not found when a project does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/projects/tuist/tuist-project/tokens/non-existing-token")

      # Then
      response = json_response(conn, :not_found)
      assert response == %{"message" => "The project tuist/tuist-project was not found"}
    end

    test "returns not found when a token does not exist", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      project =
        ProjectsFixtures.project_fixture(
          account_id: organization.account.id,
          preloads: [:account]
        )

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete(
          "/api/projects/#{project.account.name}/#{project.name}/tokens/0fcc7a05-4f0d-490d-8545-1fe3171a2880"
        )

      # Then
      response = json_response(conn, :not_found)

      assert response == %{
               "message" =>
                 "The #{project.account.name}/#{project.name} project token 0fcc7a05-4f0d-490d-8545-1fe3171a2880 was not found"
             }
    end

    test "returns bad request when a token is invalid", %{conn: conn} do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      project =
        ProjectsFixtures.project_fixture(
          account_id: organization.account.id,
          preloads: [:account]
        )

      conn =
        conn
        |> TuistCloudWeb.Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> delete("/api/projects/#{project.account.name}/#{project.name}/tokens/invalid-token")

      # Then
      response = json_response(conn, :bad_request)

      assert response == %{
               "message" =>
                 "The provided token ID invalid-token is not valid. Make sure to pass a valid identifier."
             }
    end
  end
end
