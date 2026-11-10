defmodule Tuist.Accounts.OIDCTrustPolicyTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @attrs %{
    name: "Production workload",
    issuer: "https://identity.example/tenant",
    jwks_url: "https://keys.example/jwks.json",
    audience: "tuist",
    claims: %{"sub" => "deploy:production", "project_id" => 123, "protected" => true}
  }

  setup do
    project = ProjectsFixtures.project_fixture(preload: [:account])
    %{project: project, account: project.account, attrs: @attrs}
  end

  test "accepts exact scalar identity claims and a separate public HTTPS key origin" do
    assert OIDCTrustPolicy.changeset(@attrs).valid?
    assert OIDCTrustPolicy.changeset(Map.delete(@attrs, :audience)).valid?
  end

  test "requires bounded fields and exact scalar claims, without project selection" do
    for field <- [:name, :issuer, :jwks_url, :audience, :claims] do
      refute OIDCTrustPolicy.changeset(Map.put(@attrs, field, nil)).valid?
    end

    for claims <- [
          %{},
          %{"sub" => nil},
          %{"groups" => ["admin"]},
          %{"nested" => %{"id" => "1"}},
          %{"id" => 1.0},
          %{"id" => 9_223_372_036_854_775_808},
          %{"sub" => ""},
          %{"exp" => 123},
          %{"aud" => "tuist"},
          Map.new(1..11, &{to_string(&1), "value"}),
          %{"sub" => String.duplicate("a", 513)}
        ] do
      refute OIDCTrustPolicy.changeset(%{@attrs | claims: claims}).valid?
    end

    refute OIDCTrustPolicy.changeset(%{@attrs | name: String.duplicate("a", 101)}).valid?
    refute OIDCTrustPolicy.changeset(%{@attrs | audience: String.duplicate("a", 256)}).valid?
  end

  test "rejects insecure URLs, credentials, fragments and issuer queries" do
    for field <- [:issuer, :jwks_url],
        value <- ["http://example.com", "https://user:pass@example.com", "https://example.com/#fragment", "https:///path"] do
      refute OIDCTrustPolicy.changeset(Map.put(@attrs, field, value)).valid?
    end

    refute OIDCTrustPolicy.changeset(%{@attrs | issuer: "https://example.com/?tenant=a"}).valid?
    assert OIDCTrustPolicy.changeset(%{@attrs | jwks_url: "https://example.com/keys?version=2"}).valid?
  end

  test "built-in issuers and reserved prefixes cannot be overridden" do
    for issuer <- [
          "https://token.actions.githubusercontent.com",
          "https://token.actions.githubusercontent.com/enterprise",
          "https://token.actions.githubusercontent.com/enterprise/extra",
          "https://token.builds.bitrise.io",
          "https://oidc.circleci.com/org/tenant"
        ] do
      refute OIDCTrustPolicy.changeset(%{@attrs | issuer: issuer}).valid?
    end
  end

  test "creation, listing, deletion and unique names are account scoped", %{
    account: account,
    attrs: attrs
  } do
    other = ProjectsFixtures.project_fixture(preload: [:account])
    assert {:ok, policy} = Accounts.create_oidc_trust_policy(account, Map.put(attrs, :account_id, other.account_id))
    assert policy.account_id == account.id
    assert [%{id: id}] = Accounts.list_oidc_trust_policies(account)
    assert id == policy.id
    assert [] = Accounts.list_oidc_trust_policies(other.account)
    assert {:error, changeset} = Accounts.create_oidc_trust_policy(account, attrs)
    assert %{name: [_]} = errors_on(changeset)
    assert {:ok, _} = Accounts.create_oidc_trust_policy(other.account, attrs)
    assert {:error, :not_found} = Accounts.delete_oidc_trust_policy(other.account, policy.id)
    assert {:ok, _} = Accounts.delete_oidc_trust_policy(account, policy.id)
  end

  test "policies can be created and verified before the account has any projects", context do
    Repo.delete!(context.project)
    assert {:ok, policy} = Accounts.create_oidc_trust_policy(context.account, context.attrs)
    assert [candidate] = Accounts.oidc_trust_candidates(@attrs.issuer, context.account.name, verified_claims())
    assert candidate.id == policy.id
    assert {:ok, account} = Accounts.oidc_account_by_grants(identity(context.account, policy))
    assert account.id == context.account.id
  end

  test "candidate lookup returns each account policy once, independent of project count", context do
    {:ok, policy} = Accounts.create_oidc_trust_policy(context.account, context.attrs)
    for _ <- 1..3, do: ProjectsFixtures.project_fixture(account: context.account)

    assert [candidate] =
             Accounts.oidc_trust_candidates(@attrs.issuer, String.upcase(context.account.name), verified_claims())

    assert candidate.id == policy.id
  end

  test "fresh issuance rejects changed policy content, account and deletion", context do
    {:ok, policy} = Accounts.create_oidc_trust_policy(context.account, context.attrs)
    identity = identity(context.account, policy)
    assert {:ok, _} = Accounts.oidc_account_by_grants(identity)

    for {field, value} <- [
          jwks_url: "https://different.example/keys",
          issuer: "https://different.example",
          audience: "untrusted-audience",
          claims: %{"sub" => "other"}
        ] do
      changed = Repo.update!(Ecto.Changeset.change(policy, %{field => value}))
      assert {:error, :invalid_signature} = Accounts.oidc_account_by_grants(identity)
      Repo.update!(Ecto.Changeset.change(changed, %{field => Map.fetch!(policy, field)}))
    end

    other = ProjectsFixtures.project_fixture(preload: [:account])

    assert {:error, :invalid_signature} =
             Accounts.oidc_account_by_grants(%{identity | account_handle: other.account.name})

    {:ok, _} = Accounts.delete_oidc_trust_policy(context.account, policy.id)
    assert {:error, :invalid_signature} = Accounts.oidc_account_by_grants(identity)
  end

  test "project deletion retains the identity; account deletion removes it", context do
    {:ok, policy} = Accounts.create_oidc_trust_policy(context.account, context.attrs)
    Repo.delete!(context.project)
    assert [%{id: id}] = Accounts.list_oidc_trust_policies(context.account)
    assert id == policy.id
    assert {:ok, _} = Accounts.oidc_account_by_grants(identity(context.account, policy))
    Repo.delete!(context.account)
    refute Repo.get(OIDCTrustPolicy, policy.id)
    assert {:error, :invalid_signature} = Accounts.oidc_account_by_grants(identity(context.account, policy))
  end

  test "an account can have at most twenty policies", %{account: account, attrs: attrs} do
    for i <- 1..20 do
      assert {:ok, _} = Accounts.create_oidc_trust_policy(account, %{attrs | name: "Policy #{i}"})
    end

    assert {:error, changeset} = Accounts.create_oidc_trust_policy(account, %{attrs | name: "Overflow"})
    assert %{name: [_]} = errors_on(changeset)
    assert length(Accounts.list_oidc_trust_policies(account)) == 20
  end

  test "policy matching preserves JSON scalar types and requires every claim" do
    policy = struct!(OIDCTrustPolicy, @attrs)
    claims = verified_claims()
    assert OIDCTrustPolicy.matches?(policy, claims)

    for value <- ["123", 123.0, [123], nil],
        do: refute(OIDCTrustPolicy.matches?(policy, Map.put(claims, "project_id", value)))

    refute OIDCTrustPolicy.matches?(policy, Map.delete(claims, "sub"))
  end

  defp verified_claims, do: Map.merge(@attrs.claims, %{"iss" => @attrs.issuer, "aud" => ["other", "tuist"]})

  defp identity(account, policy) do
    %{
      account_handle: account.name,
      grants: [%{policy_id: policy.id, jwks_url: policy.jwks_url, claims: verified_claims()}]
    }
  end
end
