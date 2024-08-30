defmodule Tuist.ProjectsTest do
  alias Tuist.Base64
  alias Tuist.Projects.ProjectToken
  alias Tuist.Billing
  alias Tuist.CommandEvents
  alias Tuist.CommandEventsFixtures
  alias Tuist.Accounts.ProjectAccount
  alias Tuist.AccountsFixtures
  alias Tuist.ProjectsFixtures
  alias Tuist.Projects
  alias Tuist.Accounts
  use Tuist.DataCase, async: true
  use Mimic

  setup do
    Billing
    |> stub(:start_trial, fn _ -> {:ok, %{}} end)

    :ok
  end

  test "returns command average duration" do
    # Given
    organization = AccountsFixtures.organization_fixture(name: "tuist")
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(name: "tuist-project", account_id: account.id)

    # When
    {:ok, got} = Projects.get_project_by_slug("tuist/tuist-project")

    # Then
    assert got == project
  end

  test "returns all projects associated with a user" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)
    organization_two = AccountsFixtures.organization_fixture()
    account_two = Accounts.get_account_from_organization(organization_two)
    ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    got = Projects.get_all_project_accounts(user)

    # Then
    assert [
             %ProjectAccount{
               handle: "#{account.name}/#{project.name}",
               account: account,
               project: project
             }
           ] == got
  end

  test "returns all projects associated with a user's based on a google hosted domain" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

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

    Accounts.update_organization(organization, %{
      sso_provider: :google,
      sso_organization_id: "tuist.io"
    })

    # When
    got = Projects.get_all_project_accounts(user)

    # Then
    assert [
             "#{account.name}/#{project.name}"
           ] == got |> Enum.map(& &1.handle)
  end

  test "returns missing handle or project name" do
    assert {:error, :missing_handle_or_project_name} == Projects.get_project_by_slug("tuist")
  end

  describe "get_project_account_by_project_id/1" do
    test "returns nil if a project does not exist" do
      assert nil == Projects.get_project_account_by_project_id(1)
    end

    test "returns project account" do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got = Projects.get_all_project_accounts(account)

      # Then
      assert ["#{account.name}/#{project.name}"] == Enum.map(got, & &1.handle)
    end
  end

  describe "get_project_and_account_handles_from_full_handle/1" do
    test "returns :invalid_full_handle error if full handle contains only one handle" do
      assert {:error, :invalid_full_handle} ==
               Projects.get_project_and_account_handles_from_full_handle("tuist")
    end

    test "returns :invalid_full_handle error if full handle contains only more than two handles" do
      assert {:error, :invalid_full_handle} ==
               Projects.get_project_and_account_handles_from_full_handle("tuist-org/tuist/tuist")
    end

    test "returns project and account handles" do
      assert {:ok, %{account_handle: "tuist-org", project_handle: "tuist"}} ==
               Projects.get_project_and_account_handles_from_full_handle("tuist-org/tuist")
    end
  end

  describe "delete_project/1" do
    test "deletes a project" do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "generate",
          project_id: project.id
        )

      # When
      Projects.delete_project(project)

      # Then
      assert nil == Projects.get_project_by_id(project.id)
      assert nil == CommandEvents.get_command_event_by_id(command_event.id)
    end
  end

  describe "get_all_project_accounts/1" do
    test "get all project accounts for an account" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got = Projects.get_all_project_accounts(account)

      # Then
      assert [
               %ProjectAccount{
                 handle: "#{account.name}/#{project.name}",
                 account: account,
                 project: project
               }
             ] == got
    end

    test "get all project accounts for a user" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project_one = ProjectsFixtures.project_fixture(account_id: account.id)
      user = AccountsFixtures.user_fixture()
      user_account = Accounts.get_account_from_user(user)
      Accounts.add_user_to_organization(user, organization, role: :user)

      project_two =
        ProjectsFixtures.project_fixture(account_id: user_account.id)

      # When
      got = Projects.get_all_project_accounts(user)

      # Then
      assert [
               %ProjectAccount{
                 handle: "#{account.name}/#{project_one.name}",
                 account: account,
                 project: project_one
               },
               %ProjectAccount{
                 handle: "#{user_account.name}/#{project_two.name}",
                 account: user_account,
                 project: project_two
               }
             ]
             |> Enum.sort_by(& &1.handle) == got |> Enum.sort_by(& &1.handle)
    end
  end

  describe "get_project_by_account_and_project_handles/2" do
    test "returns the project if it exists doing a case-insensitive search" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got =
        Projects.get_project_by_account_and_project_handles(
          String.upcase(account.name),
          String.upcase(project.name)
        )

      # Then
      assert got == project
    end
  end

  describe "get_project_tokens/1" do
    test "returns project's tokens" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, token_one} =
        Projects.create_project_token(project)
        |> Projects.get_project_token()

      {:ok, token_two} =
        Projects.create_project_token(project)
        |> Projects.get_project_token()

      _token_three = Projects.create_project_token(ProjectsFixtures.project_fixture())

      # When
      got = Projects.get_project_tokens(project)

      # Then
      assert got |> Enum.sort_by(& &1.id) == [token_one, token_two] |> Enum.sort_by(& &1.id)
    end

    test "returns empty array if there are no project's tokens" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_project_tokens(project)

      # Then
      assert [] == got
    end
  end

  describe "get_project_token/1" do
    test "returns project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      token = Projects.create_project_token(project)

      # When
      {:ok, got} = Projects.get_project_token(token)

      # Then
      [_audience, token_id, _token_hash] = String.split(token, "_")
      assert got.id == token_id
    end

    test "returns invalid if the token is invalid" do
      # When
      got = Projects.get_project_token("invalid-token")

      # Then
      assert {:error, :invalid_token} == got
    end

    test "returns not found if the token does not exist" do
      # When
      got = Projects.get_project_token("tuist_0fcc7a05-4f0d-490d-8545-1fe3171a2880_some-hash")

      # Then
      assert {:error, :not_found} == got
    end
  end

  describe "get_project_by_full_token/1" do
    test "returns project with a token" do
      # Given
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)

      # When
      got = Projects.get_project_by_full_token(token)

      # Then
      assert got == project
    end

    test "returns project with a legacy token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_project_by_full_token(project.token)

      # Then
      assert got == project
    end

    test "returns nil when the token does not exist" do
      # When
      got = Projects.get_project_by_full_token("some-non-existing-token")

      # Then
      assert got == nil
    end
  end

  describe "get_project_token_by_id/2" do
    test "returns project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, token} =
        Projects.create_project_token(project)
        |> Projects.get_project_token()

      # When
      got = Projects.get_project_token_by_id(project, token.id)

      # Then
      assert got == token
    end

    test "returns nil if the token does not exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_project_token_by_id(project, "01909854-f9d1-7f9d-8956-b59155b0d8cc")

      # Then
      assert got == nil
    end
  end

  describe "create_project_token/1" do
    test "creates project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      Base64
      |> expect(:encode, fn _ -> "generated-hash" end)

      # When
      got = Projects.create_project_token(project)

      # Then
      %{id: token_id} = Repo.one(ProjectToken)
      assert "tuist_#{token_id}_generated-hash" == got
    end
  end

  describe "revoke_project_token/1" do
    test "revokes project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, token} =
        Projects.create_project_token(project)
        |> Projects.get_project_token()

      # When
      Projects.revoke_project_token(token)

      # Then
      assert [] == Projects.get_project_tokens(project)
    end
  end

  describe "legacy_token?/1" do
    test "returns true if the token is a legacy token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.legacy_token?(project.token)

      # Then
      assert got == true
    end

    test "returns false if the token is not a legacy token" do
      # Given
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)

      # When
      got = Projects.legacy_token?(token)

      # Then
      assert got == false
    end
  end

  describe "get_repository_url/1" do
    test "returns the repository URL" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_provider: :github,
          vcs_repository_full_handle: "tuist/tuist"
        )

      # When
      got = Projects.get_repository_url(project)

      # Then
      assert got == "https://github.com/tuist/tuist"
    end

    test "returns nil if the project does not have a vcs" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_repository_url(project)

      # Then
      assert got == nil
    end
  end
end
