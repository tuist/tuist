defmodule Tuist.Projects.FlyOIDCTrustPolicyTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Projects
  alias Tuist.Projects.FlyOIDCTrustPolicy
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @attrs %{
    issuer: "https://oidc.fly.io/example-org",
    organization_id: "123",
    application_id: "456"
  }

  test "requires an exact Fly organization issuer and stable numeric IDs" do
    assert FlyOIDCTrustPolicy.changeset(@attrs).valid?

    for issuer <- [
          "https://example.com",
          "http://oidc.fly.io/org",
          "https://oidc.fly.io/org/extra",
          "https://oidc.fly.io/../"
        ] do
      refute FlyOIDCTrustPolicy.changeset(%{@attrs | issuer: issuer}).valid?
    end

    for field <- [:issuer, :organization_id, :application_id], value <- [nil, "", "*"] do
      refute FlyOIDCTrustPolicy.changeset(Map.put(@attrs, field, value)).valid?
    end
  end

  test "policies are project-scoped, unique, and cannot be assigned through submitted project IDs" do
    project = ProjectsFixtures.project_fixture()
    other = ProjectsFixtures.project_fixture()

    assert {:ok, policy} = Projects.create_fly_oidc_trust_policy(project, Map.put(@attrs, :project_id, other.id))
    assert policy.project_id == project.id
    assert [^policy] = Projects.list_fly_oidc_trust_policies(project)
    assert [] = Projects.list_fly_oidc_trust_policies(other)
    assert {:error, changeset} = Projects.create_fly_oidc_trust_policy(project, @attrs)
    assert %{issuer: [_]} = errors_on(changeset)
    assert {:error, :not_found} = Projects.delete_fly_oidc_trust_policy(other, policy.id)
    assert {:ok, _} = Projects.delete_fly_oidc_trust_policy(project, policy.id)
    assert [] = Projects.list_fly_oidc_trust_policies(project)
  end

  test "identity lookup requires all three exact matches and ignores VCS connections" do
    project = ProjectsFixtures.project_fixture()
    ProjectsFixtures.project_fixture(vcs_connection: [repository_full_handle: "tuist/tuist"])
    {:ok, _} = Projects.create_fly_oidc_trust_policy(project, @attrs)

    assert [%{id: id}] = Projects.projects_by_fly_oidc_identity(@attrs)
    assert id == project.id

    for {field, value} <- [
          {:issuer, "https://oidc.fly.io/other-org"},
          {:organization_id, "999"},
          {:application_id, "999"}
        ] do
      assert [] = Projects.projects_by_fly_oidc_identity(Map.put(@attrs, field, value))
    end
  end

  test "deleting a project deletes its trust policies" do
    project = ProjectsFixtures.project_fixture()
    {:ok, policy} = Projects.create_fly_oidc_trust_policy(project, @attrs)
    Tuist.Repo.delete!(project)
    refute Tuist.Repo.get(FlyOIDCTrustPolicy, policy.id)
  end
end
