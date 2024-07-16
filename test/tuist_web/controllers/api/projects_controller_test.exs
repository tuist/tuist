defmodule TuistWeb.API.ProjectsControllerTest do
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures
  alias Tuist.Accounts
  alias Tuist.Projects
  alias TuistWeb.Authentication
  use TuistWeb.ConnCase, async: true
  use Mimic

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io", preloads: [:account])
    %{user: user}
  end

  describe "POST /api/projects" do
    test "returns newly created personal project", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "#{user.account.name}/my-project")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => response["id"],
               "full_name" => "#{user.account.name}/my-project",
               "token" => response["token"]
             }
    end

    test "returns newly created personal project using just project_name", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", name: "my-project")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => response["id"],
               "full_name" => "tuist/my-project",
               "token" => response["token"]
             }
    end

    test "returns newly created project for a given organization",
         %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = Accounts.create_organization(%{name: "tuist-org", creator: user})
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "tuist-org/my-project")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => response["id"],
               "full_name" => "tuist-org/my-project",
               "token" => response["token"]
             }
    end

    test "returns newly created project for a given organization using project and organization names",
         %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = Accounts.create_organization(%{name: "tuist-org", creator: user})
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", name: "my-project", organization: "tuist-org")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => response["id"],
               "full_name" => "tuist-org/my-project",
               "token" => response["token"]
             }
    end

    test "returns an error if the provided account doesn't exist", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "non-existing-org/my-project")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{
               "message" => "The account non-existing-org was not found"
             }
    end

    test "returns an error if a user can't create projects for a given organization", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "tuist-org/my-project")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" =>
                 "You don't have permission to create projects for the tuist-org account."
             }
    end

    test "returns bad request when organization contains a dot", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "tuist-org/my.project")

      # Then
      response = json_response(conn, :bad_request)

      assert response == %{
               "message" =>
                 "Project name can't contain a dot. Please use a different name, such as my-project."
             }
    end

    test "returns bad request when the full handle contains only a project or an account name", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "tuist-org")

      # Then
      response = json_response(conn, :bad_request)

      assert response == %{
               "message" =>
                 "The project full handle tuist-org is not in the format of account-handle/project-handle."
             }
    end

    test "returns bad request when the full handle contains extra handles", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "tuist-org/my-project/extra-handle")

      # Then
      response = json_response(conn, :bad_request)

      assert response == %{
               "message" =>
                 "The project full handle tuist-org/my-project/extra-handle is not in the format of account-handle/project-handle."
             }
    end

    test "returns project exists error", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)

      Projects.create_project(%{name: "my-project", account: account})

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "#{account.name}/my-project")

      # Then
      response = json_response(conn, :bad_request)

      assert response == %{
               "message" => "Project already exists."
             }
    end
  end

  describe "GET /api/projects" do
    test "lists all user projects", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      user_account = Accounts.get_account_from_user(user)

      organization = Accounts.create_organization(%{name: "tuist-org", creator: user})
      organization_account = Accounts.get_account_from_organization(organization)
      Accounts.add_user_to_organization(user, organization)

      project_one = ProjectsFixtures.project_fixture(account_id: organization_account.id)
      project_two = ProjectsFixtures.project_fixture(account_id: user_account.id)

      # When
      conn =
        conn
        |> get("/api/projects")

      # Then
      response = json_response(conn, :ok)

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_one.id,
                 "full_name" => "tuist-org/#{project_one.name}",
                 "token" => project_one.token
               }
             end) != nil

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_two.id,
                 "full_name" => "tuist/#{project_two.name}",
                 "token" => project_two.token
               }
             end) != nil

      assert length(response["projects"]) == 2
    end

    test "lists all user projects when associated with a google hosted domain", %{conn: conn} do
      # Given
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.io"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      conn =
        conn
        |> Authentication.put_current_user(user)

      user_account = Accounts.get_account_from_user(user)

      organization = Accounts.create_organization(%{name: "tuist-org", creator: user})

      Accounts.update_organization(organization, %{
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      })

      organization_account = Accounts.get_account_from_organization(organization)

      project_one = ProjectsFixtures.project_fixture(account_id: organization_account.id)
      project_two = ProjectsFixtures.project_fixture(account_id: user_account.id)

      # When
      conn =
        conn
        |> get("/api/projects")

      # Then
      response = json_response(conn, :ok)

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_one.id,
                 "full_name" => "tuist-org/#{project_one.name}",
                 "token" => project_one.token
               }
             end) != nil

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_two.id,
                 "full_name" => "tuist/#{project_two.name}",
                 "token" => project_two.token
               }
             end) != nil

      assert length(response["projects"]) == 2
    end
  end

  describe "GET /api/projects/{account_name}/{project_name}" do
    test "Returns a user's project by its handle", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> get("/api/projects/#{account.name}/#{project.name}")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => project.id,
               "full_name" => "#{account.name}/#{project.name}",
               "token" => project.token
             }
    end

    test "Returns an organization's project by its handle", %{
      conn: conn,
      user: user
    } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      Accounts.add_user_to_organization(user, organization)

      # When
      conn =
        conn
        |> get("/api/projects/#{account.name}/#{project.name}")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => project.id,
               "full_name" => "#{account.name}/#{project.name}",
               "token" => project.token
             }
    end

    test "Returns a not found error if an account does not exist", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> get("/api/projects/non-existing-account/non-existing-project")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{
               "message" => "Account non-existing-account not found."
             }
    end

    test "Returns a not found error if a project does not exist", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)

      # When
      conn =
        conn
        |> get("/api/projects/#{account.name}/non-existing-project")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{
               "message" => "Project tuist/non-existing-project not found."
             }
    end

    test "Returns an unauthenticated error if a user doesn't have a permission to read the project",
         %{
           conn: conn,
           user: user
         } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> get("/api/projects/#{account.name}/#{project.name}")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "You don't have permission to read the #{project.name} project."
             }
    end
  end

  describe "DELETE /api/projects/{id}" do
    test "Deletes a given project", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> delete("/api/projects/#{project.id}")

      # Then
      response = response(conn, :no_content)

      assert response == ""

      refute Projects.get_project_by_id(project.id)
    end

    test "Returns a not found error if a project does not exist", %{conn: conn, user: user} do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      # When
      conn =
        conn
        |> delete("/api/projects/1")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{
               "message" => "Project not found."
             }
    end

    test "Returns an unauthenticated error if a user doesn't have a permission to delete the project",
         %{
           conn: conn,
           user: user
         } do
      # Given
      conn =
        conn
        |> Authentication.put_current_user(user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> delete("/api/projects/#{project.id}")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" =>
                 "You don't have permission to delete the #{account.name}/#{project.name} project."
             }
    end
  end
end
