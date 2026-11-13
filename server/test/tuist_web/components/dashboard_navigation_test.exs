defmodule TuistWeb.DashboardNavigationTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.DashboardNavigation

  test "viewer discovery does not advertise administrative destinations" do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    :ok = Accounts.add_user_to_organization(user, organization, role: :viewer)
    project = [account_id: organization.account.id] |> ProjectsFixtures.project_fixture() |> Repo.preload(:account)
    pages = DashboardNavigation.pages(user, organization.account, project)
    paths = Enum.map(pages, & &1.path)
    assert "/#{organization.account.name}/projects" in paths
    refute Enum.any?(paths, &String.contains?(&1, ["/settings", "/billing", "/webhooks"]))
    refute "/#{organization.account.name}/cache" in paths

    owner = AccountsFixtures.user_fixture(preload: [:account])
    owner_pages = DashboardNavigation.pages(owner, owner.account, nil)
    owner_paths = Enum.map(owner_pages, & &1.path)
    settings = Enum.find(owner_pages, &(&1.path == "/#{owner.account.name}/settings"))
    assert settings.title == "Account Settings"
    assert settings.description == "Account: #{owner.account.name}"
    assert "/#{owner.account.name}/settings/authentication" in owner_paths
    assert "/#{owner.account.name}/billing" in owner_paths
  end

  test "feature-disabled destinations are absent from the same catalog used by the sidebar" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(FeatureFlags, :runners_enabled?, fn _ -> false end)
    stub(FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    stub(FeatureFlags, :ai_enabled?, fn _ -> false end)
    paths = user |> DashboardNavigation.pages(user.account, nil) |> Enum.map(& &1.path)
    refute Enum.any?(paths, &String.contains?(&1, ["/runners", "/sandboxes", "/ai"]))
  end

  test "project settings respect native build-system capabilities" do
    user = AccountsFixtures.user_fixture(preload: [:account])

    for system <- [:xcode, :gradle, :bazel, :mix, :cargo, :once] do
      project =
        [account_id: user.account.id, build_system: system]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      pages = DashboardNavigation.pages(user, user.account, project)
      paths = Enum.map(pages, & &1.path)
      root = "/#{user.account.name}/#{project.name}/settings"
      assert root in paths
      assert Enum.find(pages, &(&1.path == root)).description == ""
      assert Enum.find(pages, &(&1.path == root)).title == "Settings"
      integrations = Enum.find(pages, &(&1.path == root <> "/integrations"))
      assert integrations.title == "Integrations"
      assert integrations.hierarchy == "Settings"
      refute Enum.any?(pages, &(String.downcase(&1.title) == String.downcase(&1.description)))
      assert (root <> "/notifications") in paths == (system == :xcode)
      assert (root <> "/automations") in paths == system in [:xcode, :bazel, :mix, :cargo]
    end
  end
end
