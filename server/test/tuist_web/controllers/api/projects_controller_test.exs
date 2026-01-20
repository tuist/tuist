defmodule TuistWeb.API.ProjectsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])
    %{user: user}
  end

  describe "POST /api/projects" do
    test "returns newly created personal project", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
               "token" => response["token"],
               "default_branch" => "main",
               "repository_url" => nil,
               "visibility" => "private"
             }
    end

    test "returns newly created personal project using just project_name", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
               "token" => response["token"],
               "default_branch" => "main",
               "repository_url" => nil,
               "visibility" => "private"
             }
    end

    test "returns newly created project for a given organization",
         %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      {:ok, organization} = Accounts.create_organization(%{name: "tuist-org", creator: user})
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
               "token" => response["token"],
               "default_branch" => "main",
               "repository_url" => nil,
               "visibility" => "private"
             }
    end

    test "returns newly created project for a given organization using project and organization names",
         %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      {:ok, organization} = Accounts.create_organization(%{name: "tuist-org", creator: user})
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
               "token" => response["token"],
               "default_branch" => "main",
               "repository_url" => nil,
               "visibility" => "private"
             }
    end

    test "returns an error if the provided account doesn't exist", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
      conn = Authentication.put_current_user(conn, user)

      AccountsFixtures.organization_fixture(name: "tuist-org")

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects", full_handle: "tuist-org/my-project")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "You don't have permission to create projects for the tuist-org account."
             }
    end

    test "returns bad request when organization contains a dot", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
               "message" => "Project name can't contain a dot. Please use a different name, such as my-project."
             }
    end

    test "returns bad request when the full handle contains only a project or an account name", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
               "message" => "The project full handle tuist-org is not in the format of account-handle/project-handle."
             }
    end

    test "returns bad request when the full handle contains extra handles", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

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
      conn = Authentication.put_current_user(conn, user)

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
      conn = Authentication.put_current_user(conn, user)

      user_account = Accounts.get_account_from_user(user)

      {:ok, organization} = Accounts.create_organization(%{name: "tuist-org", creator: user})
      organization_account = Accounts.get_account_from_organization(organization)
      Accounts.add_user_to_organization(user, organization)

      project_one = ProjectsFixtures.project_fixture(account_id: organization_account.id)
      project_two = ProjectsFixtures.project_fixture(account_id: user_account.id)

      # When
      conn = get(conn, "/api/projects")

      # Then
      response = json_response(conn, :ok)

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_one.id,
                 "full_name" => "tuist-org/#{project_one.name}",
                 "token" => project_one.token,
                 "default_branch" => project_one.default_branch,
                 "visibility" => Atom.to_string(project_one.visibility)
               }
             end)

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_two.id,
                 "full_name" => "tuist/#{project_two.name}",
                 "token" => project_two.token,
                 "default_branch" => project_two.default_branch,
                 "visibility" => Atom.to_string(project_two.visibility)
               }
             end)

      assert length(response["projects"]) == 2
    end

    test "lists all user projects when associated with a google hosted domain", %{conn: conn} do
      # Given
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :google,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          },
          extra: %{
            raw_info: %{
              user: %{
                "hd" => "tuist.io"
              }
            }
          }
        })

      conn = Authentication.put_current_user(conn, user)

      user_account = Accounts.get_account_from_user(user)

      {:ok, organization} = Accounts.create_organization(%{name: "tuist-org", creator: user})

      Accounts.update_organization(organization, %{
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      })

      organization_account = Accounts.get_account_from_organization(organization)

      project_one = ProjectsFixtures.project_fixture(account_id: organization_account.id)
      project_two = ProjectsFixtures.project_fixture(account_id: user_account.id)

      # When
      conn = get(conn, "/api/projects")

      # Then
      response = json_response(conn, :ok)

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_one.id,
                 "full_name" => "tuist-org/#{project_one.name}",
                 "token" => project_one.token,
                 "default_branch" => project_one.default_branch,
                 "visibility" => Atom.to_string(project_one.visibility)
               }
             end)

      assert Enum.find_value(response["projects"], fn value ->
               value == %{
                 "id" => project_two.id,
                 "full_name" => "tuist/#{project_two.name}",
                 "token" => project_two.token,
                 "default_branch" => project_two.default_branch,
                 "visibility" => Atom.to_string(project_two.visibility)
               }
             end)

      assert length(response["projects"]) == 2
    end

    test "lists all projects for an authenticated account subject", %{conn: conn} do
      account = AccountsFixtures.account_fixture()
      project_one = ProjectsFixtures.project_fixture(account_id: account.id)
      project_two = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: []})
        |> get(~p"/api/projects")

      response = json_response(conn, :ok)

      handles = Enum.map(response["projects"], & &1["full_name"])

      assert Enum.sort(handles) ==
               Enum.sort([
                 "#{account.name}/#{project_one.name}",
                 "#{account.name}/#{project_two.name}"
               ])
    end

    test "lists the current project for a project token subject", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()

      conn =
        conn
        |> Authentication.put_current_project(project)
        |> get(~p"/api/projects")

      response = json_response(conn, :ok)

      assert response["projects"] == [
               %{
                 "id" => project.id,
                 "full_name" => "#{project.account.name}/#{project.name}",
                 "token" => project.token,
                 "default_branch" => project.default_branch,
                 "visibility" => Atom.to_string(project.visibility)
               }
             ]
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/projects")
      response = json_response(conn, :unauthorized)
      assert response["message"] == "You need to be authenticated to access this resource."
    end
  end

  describe "GET /api/projects/{account_name}/{project_name}" do
    test "Returns a user's project by its handle", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn = get(conn, "/api/projects/#{account.name}/#{project.name}")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => project.id,
               "full_name" => "#{account.name}/#{project.name}",
               "token" => project.token,
               "default_branch" => project.default_branch,
               "repository_url" => nil,
               "visibility" => "private"
             }
    end

    test "Returns an organization's project by its handle", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      Accounts.add_user_to_organization(user, organization)

      # When
      conn = get(conn, "/api/projects/#{account.name}/#{project.name}")

      # Then
      response = json_response(conn, :ok)

      assert response == %{
               "id" => project.id,
               "full_name" => "#{account.name}/#{project.name}",
               "token" => project.token,
               "default_branch" => project.default_branch,
               "repository_url" => nil,
               "visibility" => "private"
             }
    end

    test "Returns a not found error if an account does not exist", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = get(conn, "/api/projects/non-existing-account/non-existing-project")

      # Then
      response = json_response(conn, :not_found)

      assert response == %{
               "message" => "Account non-existing-account not found."
             }
    end

    test "Returns a not found error if a project does not exist", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)

      # When
      conn = get(conn, "/api/projects/#{account.name}/non-existing-project")

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
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn = get(conn, "/api/projects/#{account.name}/#{project.name}")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "You don't have permission to read the #{project.name} project."
             }
    end
  end

  describe "PUT /api/projects/:account_handle/:project_handle" do
    test "updates a project with a default branch", %{conn: conn, user: user} do
      # Given

      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/projects/#{account.name}/#{project.name}",
          default_branch: "new-default-branch"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["default_branch"] == "new-default-branch"
    end

    test "updates a project with public visibility", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/projects/#{account.name}/#{project.name}",
          visibility: "public"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["visibility"] == "public"
      assert Projects.get_project_by_id(project.id).visibility == :public
    end

    test "updates a project's default branch and visibility", %{
      conn: conn
    } do
      # Given
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          }
        })

      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/projects/#{account.name}/#{project.name}",
          default_branch: "develop",
          visibility: "public"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["default_branch"] == "develop"
      assert response["visibility"] == "public"
    end

    test "returns :forbidden when user is not an admin of an organization", %{
      conn: conn,
      user: user
    } do
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture(name: "tuist-org")
      Accounts.add_user_to_organization(user, organization)
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/projects/#{account.name}/#{project.name}",
          default_branch: "new-default-branch"
        )

      # Then
      response = json_response(conn, :forbidden)

      assert response["message"] ==
               "The authenticated subject is not authorized to perform this action."
    end

    test "returns :not_found when project does not exist", %{conn: conn, user: user} do
      conn = Authentication.put_current_user(conn, user)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/projects/tuist/non-existing-project",
          default_branch: "new-default-branch"
        )

      response = json_response(conn, :not_found)
      assert response["message"] == "Project tuist/non-existing-project was not found."
    end
  end

  describe "DELETE /api/projects/{id}" do
    test "Deletes a given project", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn = delete(conn, "/api/projects/#{project.id}")

      # Then
      response = response(conn, :no_content)

      assert response == ""

      refute Projects.get_project_by_id(project.id)
    end

    test "Returns a not found error if a project does not exist", %{conn: conn, user: user} do
      # Given
      conn = Authentication.put_current_user(conn, user)

      # When
      conn = delete(conn, "/api/projects/1")

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
      conn = Authentication.put_current_user(conn, user)

      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      conn = delete(conn, "/api/projects/#{project.id}")

      # Then
      response = json_response(conn, :forbidden)

      assert response == %{
               "message" => "You don't have permission to delete the #{account.name}/#{project.name} project."
             }
    end
  end
end
