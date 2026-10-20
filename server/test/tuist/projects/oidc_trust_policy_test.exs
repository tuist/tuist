defmodule Tuist.Projects.OIDCTrustPolicyTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Projects
  alias Tuist.Projects.OIDCTrustPolicy
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @attrs %{
    name: "Production workload",
    issuer: "https://identity.example/tenant",
    jwks_url: "https://keys.example/jwks.json",
    audience: "tuist",
    claims: %{"sub" => "deploy:production", "project_id" => 123, "protected" => true}
  }

  test "accepts exact scalar identity claims and a separate public HTTPS key origin" do
    assert OIDCTrustPolicy.changeset(@attrs).valid?
    assert OIDCTrustPolicy.changeset(Map.delete(@attrs, :audience)).valid?
  end

  test "requires bounded names, URLs, audience and nonempty scalar claims" do
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

  test "create and delete are project scoped and names are unique within the project" do
    project = ProjectsFixtures.project_fixture()
    other = ProjectsFixtures.project_fixture()
    assert {:ok, policy} = Projects.create_oidc_trust_policy(project, Map.put(@attrs, :project_id, other.id))
    assert policy.project_id == project.id
    assert [^policy] = Projects.list_oidc_trust_policies(project)
    assert [] = Projects.list_oidc_trust_policies(other)
    assert {:error, changeset} = Projects.create_oidc_trust_policy(project, @attrs)
    assert %{name: [_]} = errors_on(changeset)
    assert {:ok, _} = Projects.create_oidc_trust_policy(other, @attrs)
    assert {:error, :not_found} = Projects.delete_oidc_trust_policy(other, policy.id)
    assert {:ok, _} = Projects.delete_oidc_trust_policy(project, policy.id)
  end

  test "project deletion cascades policies" do
    project = ProjectsFixtures.project_fixture()
    {:ok, policy} = Projects.create_oidc_trust_policy(project, @attrs)
    Repo.delete!(project)
    refute Repo.get(OIDCTrustPolicy, policy.id)
  end

  test "a project can have at most twenty policies" do
    project = ProjectsFixtures.project_fixture()

    for i <- 1..20 do
      assert {:ok, _} = Projects.create_oidc_trust_policy(project, %{@attrs | name: "Policy #{i}"})
    end

    assert {:error, changeset} = Projects.create_oidc_trust_policy(project, %{@attrs | name: "Overflow"})
    assert %{name: [_]} = errors_on(changeset)
    assert length(Projects.list_oidc_trust_policies(project)) == 20
  end

  test "policy matching preserves JSON scalar types and requires every claim" do
    policy = struct!(OIDCTrustPolicy, @attrs)
    claims = Map.merge(@attrs.claims, %{"iss" => @attrs.issuer, "aud" => ["other", "tuist"]})
    assert OIDCTrustPolicy.matches?(policy, claims)

    for value <- ["123", 123.0, [123], nil] do
      refute OIDCTrustPolicy.matches?(policy, Map.put(claims, "project_id", value))
    end

    refute OIDCTrustPolicy.matches?(policy, Map.delete(claims, "sub"))
  end
end
