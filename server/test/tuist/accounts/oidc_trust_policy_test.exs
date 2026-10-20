defmodule Tuist.Accounts.OIDCTrustPolicyTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @attrs %{
    name: "Production workload",
    issuer: "https://identity.example/tenant",
    jwks_url: "https://keys.example/jwks.json",
    audience: "tuist",
    claims: %{"sub" => "deploy:production", "project_id" => 123, "protected" => true},
    project_ids: [1]
  }

  setup do
    project = ProjectsFixtures.project_fixture(preload: [:account])
    %{project: project, account: project.account, attrs: %{@attrs | project_ids: [project.id]}}
  end

  test "accepts exact scalar identity claims and a separate public HTTPS key origin" do
    assert OIDCTrustPolicy.changeset(@attrs).valid?
    assert OIDCTrustPolicy.changeset(Map.delete(@attrs, :audience)).valid?
  end

  test "requires bounded fields, exact scalar claims and explicit project selection" do
    for field <- [:name, :issuer, :jwks_url, :audience, :claims, :project_ids] do
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

    for ids <- [[], Enum.to_list(1..101), ["not-an-id"], [0], [-1], [9_223_372_036_854_775_808], %{"all" => true}, true] do
      refute OIDCTrustPolicy.changeset(%{@attrs | project_ids: ids}).valid?
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
    project: project,
    attrs: attrs
  } do
    other = ProjectsFixtures.project_fixture(preload: [:account])
    assert {:ok, policy} = Accounts.create_oidc_trust_policy(account, Map.put(attrs, :account_id, other.account_id))
    assert policy.account_id == account.id
    assert Enum.map(policy.projects, & &1.id) == [project.id]
    assert [%{id: id}] = Accounts.list_oidc_trust_policies(account)
    assert id == policy.id
    assert [] = Accounts.list_oidc_trust_policies(other.account)
    assert {:error, changeset} = Accounts.create_oidc_trust_policy(account, attrs)
    assert %{name: [_]} = errors_on(changeset)
    assert {:ok, _} = Accounts.create_oidc_trust_policy(other.account, %{attrs | project_ids: [other.id]})
    assert {:error, :not_found} = Accounts.delete_oidc_trust_policy(other.account, policy.id)
    assert {:ok, _} = Accounts.delete_oidc_trust_policy(account, policy.id)
  end

  test "rejects foreign, missing and empty project grants atomically", %{account: account, attrs: attrs, project: project} do
    foreign = ProjectsFixtures.project_fixture()

    for ids <- [[], [foreign.id], [project.id, foreign.id], [-1], [project.id, -1]] do
      assert {:error, changeset} = Accounts.create_oidc_trust_policy(account, %{attrs | project_ids: ids})
      assert %{project_ids: [_]} = errors_on(changeset)
      assert [] = Accounts.list_oidc_trust_policies(account)
    end
  end

  test "one identity grants only selected projects, never unselected or future projects", %{
    account: account,
    project: project,
    attrs: attrs
  } do
    second = ProjectsFixtures.project_fixture(account: account)
    ProjectsFixtures.project_fixture(account: account)
    {:ok, policy} = Accounts.create_oidc_trust_policy(account, %{attrs | project_ids: [project.id, second.id, second.id]})
    ProjectsFixtures.project_fixture(account: account)

    assert Enum.sort(Enum.map(Projects.projects_by_oidc_grants(identity(account, policy)), & &1.id)) ==
             Enum.sort([project.id, second.id])

    assert length(Accounts.oidc_trust_candidates(attrs.issuer, account.name, verified_claims())) == 1
  end

  test "fresh issuance drops removed grants and transferred projects", %{account: account, project: project, attrs: attrs} do
    second = ProjectsFixtures.project_fixture(account: account)
    foreign = ProjectsFixtures.project_fixture()
    {:ok, policy} = Accounts.create_oidc_trust_policy(account, %{attrs | project_ids: [project.id, second.id]})
    identity = identity(account, policy)
    Repo.update!(Ecto.Changeset.change(second, account_id: foreign.account_id))
    assert [%{id: id}] = Projects.projects_by_oidc_grants(identity)
    assert id == project.id

    Repo.delete_all(
      from g in "account_oidc_trust_policy_projects", where: g.policy_id == ^policy.id and g.project_id == ^project.id
    )

    assert [] = Projects.projects_by_oidc_grants(identity)
    assert [] = Accounts.oidc_trust_candidates(attrs.issuer, account.name, verified_claims())
    assert [%{projects: []}] = Accounts.list_oidc_trust_policies(account)
  end

  test "project deletion removes only its grant; account deletion removes the identity", %{
    account: account,
    project: project,
    attrs: attrs
  } do
    second = ProjectsFixtures.project_fixture(account: account)
    {:ok, policy} = Accounts.create_oidc_trust_policy(account, %{attrs | project_ids: [project.id, second.id]})
    Repo.delete!(project)
    assert [%{projects: [%{id: id}]}] = Accounts.list_oidc_trust_policies(account)
    assert id == second.id
    assert Repo.get(OIDCTrustPolicy, policy.id)
    Repo.delete!(account)
    refute Repo.get(OIDCTrustPolicy, policy.id)
    assert Repo.aggregate("account_oidc_trust_policy_projects", :count) == 0
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
