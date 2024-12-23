defmodule Tuist.AuthenticationTest do
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  use TuistTestSupport.Cases.DataCase
  alias Tuist.Authentication
  alias TuistTestSupport.Fixtures.AccountsFixtures
  use Mimic

  test "authenticated_subject returns nil if the token associated subject doesn't exist" do
    # Given
    token = unique_integer() |> Integer.to_string()

    # When
    result = Authentication.authenticated_subject(token)

    # Then
    assert result == nil
  end

  test "authenticated_subject returns the user associated to the guardian token" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_token = "some_token"

    Tuist.Guardian
    |> expect(:resource_from_token, fn ^user_token -> {:ok, user, %{}} end)

    # When/Then
    assert Authentication.authenticated_subject(user_token) == user
  end

  test "authenticated_subject returns the user associated to the token" do
    # Given
    user = AccountsFixtures.user_fixture()

    # When/Then
    assert Authentication.authenticated_subject(user.token) == user
  end

  test "authenticated_subject returns the project associated to the legacy token" do
    # Given
    project = ProjectsFixtures.project_fixture()

    # When/Then
    assert Authentication.authenticated_subject(project.token) == project
  end

  test "authenticated_subject returns the project associated to the token" do
    # Given
    project = ProjectsFixtures.project_fixture()
    token = Projects.create_project_token(project)

    # When/Then
    assert Authentication.authenticated_subject(token) == project
  end

  test "authenticated_subject return the authenticated account associated to the token" do
    # Given
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    {_, token_value} =
      Accounts.create_account_token(%{account: account, scopes: [:account_registry_read]})

    # When/Then
    assert Authentication.authenticated_subject(token_value) == %AuthenticatedAccount{
             scopes: [:account_registry_read],
             account: account
           }
  end
end
