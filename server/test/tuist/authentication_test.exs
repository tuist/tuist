defmodule Tuist.AuthenticationTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authentication
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "authenticated_subject returns nil if the token associated subject doesn't exist" do
    # Given
    token = Integer.to_string(unique_integer())

    # When
    result = Authentication.authenticated_subject(token)

    # Then
    assert result == nil
  end

  test "authenticated_subject returns the user associated to the guardian token" do
    # Given
    user = AccountsFixtures.user_fixture()
    user_token = "some_token"

    expect(Tuist.Guardian, :resource_from_token, fn ^user_token -> {:ok, user, %{}} end)

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
    assert token |> Authentication.authenticated_subject() |> Repo.preload(:account) == project
  end

  test "authenticated_subject return the authenticated account associated to the token" do
    # Given
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    {:ok, {_, token_value}} =
      Accounts.create_account_token(%{account: account, scopes: [:account_registry_read]})

    # When/Then
    assert Authentication.authenticated_subject(token_value) == %AuthenticatedAccount{
             scopes: [:account_registry_read],
             account: account
           }
  end

  test "authenticated_subject returns AuthenticatedAccount for JWT account token" do
    # Given
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    {:ok, jwt_token, _claims} =
      Authentication.encode_and_sign(
        account,
        %{
          "type" => "account",
          "scopes" => ["project_qa_run_update", "project_qa_run_step_create", "project_qa_screenshot_create"]
        },
        token_type: :access,
        ttl: {1, :hour}
      )

    # When
    result = Authentication.authenticated_subject(jwt_token)

    # Then
    assert %AuthenticatedAccount{
             account: %Account{id: account_id},
             scopes: [:project_qa_run_update, :project_qa_run_step_create, :project_qa_screenshot_create]
           } = result

    assert account_id == account.id
  end

  test "refresh/2 refreshes the account handle" do
    # Given
    %User{id: id, account: %{name: name}} =
      user = AccountsFixtures.user_fixture()

    {:ok, refresh_token, _opts} =
      Authentication.encode_and_sign(
        user,
        %{
          email: user.email,
          preferred_username: user.account.name
        },
        token_type: :refresh,
        ttl: {60, :minute}
      )

    {:ok, %User{id: ^id}, %{"preferred_username" => ^name}} =
      Tuist.Guardian.resource_from_token(refresh_token)

    # When
    new_handle = "new#{System.unique_integer()}"
    Accounts.update_account(user.account, %{name: new_handle})

    # Then
    {:ok, _old_token, {_new_refresh_token, new_claims}} =
      Authentication.refresh(refresh_token, ttl: {60, :minute})

    assert new_claims["preferred_username"] == new_handle
  end
end
