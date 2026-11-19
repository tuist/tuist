defmodule Tuist.Accounts.CredentialRevocationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.CredentialRevocation
  alias Tuist.Accounts.UserToken
  alias Tuist.Authentication
  alias Tuist.Projects
  alias Tuist.Projects.ProjectToken
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # One organization with a member, a project, and one credential of each
  # kind, all of which authenticate before the revocation.
  defp organization_with_credentials do
    member = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    Accounts.add_user_to_organization(member, organization, role: :user)
    account = organization.account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    {:ok, {_token, account_token}} =
      Accounts.create_account_token(%{account: account, scopes: ["project:cache:read"], name: "ci", all_projects: true})

    {:ok, account_jwt, _} =
      Authentication.encode_and_sign(account, %{"type" => "account", "scopes" => ["ci"]},
        token_type: :access,
        ttl: {1, :hour}
      )

    {:ok, user_jwt, _} = Authentication.encode_and_sign(member, %{}, token_type: :access, ttl: {1, :hour})

    credentials = %{
      project: Projects.create_project_token(project),
      account: account_token,
      account_jwt: account_jwt,
      user_jwt: user_jwt
    }

    session = Accounts.generate_user_session_token(member)

    for {kind, credential} <- credentials do
      assert Authentication.authenticated_subject(credential), "#{kind} should authenticate before revocation"
    end

    %{account: account, member: member, credentials: credentials, session: session}
  end

  defp authenticating(credentials) do
    for {kind, credential} <- credentials, Authentication.authenticated_subject(credential), do: kind
  end

  # Revocation compares issue times in whole seconds, so a credential minted in
  # the same second as the revocation is revoked too. Waiting a second shows the
  # other organization's credentials still work after the revocation, not only
  # that they were minted before it.
  defp next_second, do: Process.sleep(1_000)

  describe "revoke_account/1" do
    test "revokes the account's credentials and its members', and leaves other accounts alone" do
      target = organization_with_credentials()
      other = organization_with_credentials()

      assert {:ok, counts} = CredentialRevocation.revoke_account(target.account.id)
      next_second()

      assert authenticating(target.credentials) == []
      refute Accounts.get_user_by_session_token(target.session)
      # The organization's creator and the member.
      assert counts.users == 2
      assert counts.account_tokens == 1
      assert counts.project_tokens == 1

      assert Enum.sort(authenticating(other.credentials)) == Enum.sort(Map.keys(other.credentials))
      assert Accounts.get_user_by_session_token(other.session)
    end

    test "returns an error for an unknown account" do
      assert CredentialRevocation.revoke_account(-1) == {:error, :not_found}
    end
  end

  describe "revoke_everything/0" do
    test "revokes every customer credential" do
      first = organization_with_credentials()
      second = organization_with_credentials()

      CredentialRevocation.revoke_everything()

      assert authenticating(first.credentials) == []
      assert authenticating(second.credentials) == []
      assert Repo.aggregate(UserToken, :count) == 0
      assert Repo.aggregate(AccountToken, :count) == 0
      assert Repo.aggregate(ProjectToken, :count) == 0
    end

    test "rejects credentials issued before it but not those issued after" do
      %{member: member} = organization_with_credentials()

      CredentialRevocation.revoke_everything()
      next_second()

      {:ok, fresh, _} = Authentication.encode_and_sign(member, %{}, token_type: :access, ttl: {1, :hour})
      assert Authentication.authenticated_subject(fresh)
    end
  end
end
