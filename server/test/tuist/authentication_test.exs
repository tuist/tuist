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
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
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
      Accounts.create_account_token(%{account: account, scopes: ["account:registry:read"], name: "test-token"})

    # When/Then
    result = Authentication.authenticated_subject(token_value)
    assert result.scopes == ["account:registry:read"]
    assert result.account == account
    assert result.all_projects == false
    assert result.project_ids == []
  end

  test "authenticated_subject returns AuthenticatedAccount for JWT account token" do
    # Given
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    {:ok, jwt_token, _claims} =
      Authentication.encode_and_sign(
        account,
        %{
          "type" => "account",
          "scopes" => ["qa_run_update", "qa_step_create", "qa_screenshot_create"]
        },
        token_type: :access,
        ttl: {1, :hour}
      )

    # When
    %AuthenticatedAccount{
      account: %Account{id: account_id},
      scopes: ["qa_run_update", "qa_step_create", "qa_screenshot_create"]
    } = Authentication.authenticated_subject(jwt_token)

    # Then
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

  describe "encode_and_sign/3 with projects claim" do
    test "adds projects claim with user's accessible project handles" do
      # Given
      user = AccountsFixtures.user_fixture()
      project1 = ProjectsFixtures.project_fixture(account: user.account)
      project2 = ProjectsFixtures.project_fixture(account: user.account)
      CommandEventsFixtures.command_event_fixture(project_id: project1.id)
      CommandEventsFixtures.command_event_fixture(project_id: project2.id)

      # When
      {:ok, _token, claims} =
        Authentication.encode_and_sign(
          user,
          %{email: user.email},
          token_type: :access,
          ttl: {1, :hour}
        )

      # Then
      assert is_list(claims["projects"])
      assert "#{user.account.name}/#{project1.name}" in claims["projects"]
      assert "#{user.account.name}/#{project2.name}" in claims["projects"]
    end

    test "adds empty projects claim when user has no projects" do
      # Given
      user = AccountsFixtures.user_fixture()

      # When
      {:ok, _token, claims} =
        Authentication.encode_and_sign(
          user,
          %{email: user.email},
          token_type: :access,
          ttl: {1, :hour}
        )

      # Then
      assert claims["projects"] == []
    end

    test "includes projects from organization memberships" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)
      CommandEventsFixtures.command_event_fixture(project_id: project.id)

      # When
      {:ok, _token, claims} =
        Authentication.encode_and_sign(
          user,
          %{email: user.email},
          token_type: :access,
          ttl: {1, :hour}
        )

      # Then
      assert "#{organization.account.name}/#{project.name}" in claims["projects"]
    end

    test "preserves existing claims while adding projects" do
      # Given
      user = AccountsFixtures.user_fixture()
      ProjectsFixtures.project_fixture(account: user.account)

      # When
      {:ok, _token, claims} =
        Authentication.encode_and_sign(
          user,
          %{email: user.email, custom_claim: "custom_value"},
          token_type: :access,
          ttl: {1, :hour}
        )

      # Then
      assert claims["email"] == user.email
      assert claims["custom_claim"] == "custom_value"
      assert is_list(claims["projects"])
    end
  end
end
