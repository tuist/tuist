defmodule Atlas.IntegrationsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Audit.Activity
  alias Atlas.Integrations
  alias Atlas.Integrations.GitHubApp
  alias Atlas.Integrations.GitHubRepository
  alias Atlas.Repo

  defp github_app_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Test App",
        webhook_secret: "whsec_test",
        app_id: "12345",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        installation_id: "67890"
      },
      overrides
    )
  end

  describe "GitHub apps" do
    test "list_github_apps/0 returns all apps ordered by name" do
      {:ok, _} = Integrations.create_github_app(github_app_attrs(%{name: "Zebra"}))
      {:ok, _} = Integrations.create_github_app(github_app_attrs(%{name: "Alpha"}))

      apps = Integrations.list_github_apps()
      assert [%{name: "Alpha"}, %{name: "Zebra"}] = apps
    end

    test "get_github_app/1 returns the app with repositories preloaded" do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})

      fetched = Integrations.get_github_app(app.id)
      assert fetched.name == "Test App"
      assert length(fetched.repositories) == 1
    end

    test "get_github_app/1 returns nil for non-existent app" do
      assert Integrations.get_github_app(Ecto.UUID.generate()) == nil
    end

    test "create_github_app/1 with valid attrs creates an app" do
      assert {:ok, %GitHubApp{} = app} = Integrations.create_github_app(github_app_attrs())
      assert app.name == "Test App"
      assert app.app_id == "12345"

      activity = Repo.get_by!(Activity, action: "github_app.created", target_id: app.id)
      assert activity.target_label == "Test App"
      assert activity.metadata["changed_fields"] == ~w(app_id installation_id name private_key webhook_secret)
    end

    test "create_github_app/1 with missing required fields returns error" do
      assert {:error, changeset} = Integrations.create_github_app(%{name: "Incomplete"})
      assert errors_on(changeset).webhook_secret
    end

    test "update_github_app/2 updates the app" do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      {:ok, updated} = Integrations.update_github_app(app, %{name: "Updated"})
      assert updated.name == "Updated"

      activity = Repo.get_by!(Activity, action: "github_app.updated", target_id: app.id)
      assert activity.metadata["changed_fields"] == ["name"]
    end

    test "delete_github_app/1 deletes the app and its repositories" do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})

      assert {:ok, _} = Integrations.delete_github_app(app)
      assert Integrations.get_github_app(app.id) == nil
      assert Integrations.list_github_repositories(app) == []

      activity = Repo.get_by!(Activity, action: "github_app.deleted", target_id: app.id)
      assert activity.metadata["repositories_deleted"] == 1
    end
  end

  describe "GitHub repositories" do
    setup do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      %{app: app}
    end

    test "add_github_repository/2 creates a repository", %{app: app} do
      assert {:ok, %GitHubRepository{} = repo} =
               Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})

      assert repo.owner == "tuist"
      assert repo.repo == "atlas"

      activity = Repo.get_by!(Activity, action: "github_repository.added", target_id: repo.id)
      assert activity.target_label == "tuist/atlas"
      assert activity.metadata["github_app_id"] == app.id
    end

    test "add_github_repository/2 enforces uniqueness", %{app: app} do
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})

      assert {:error, changeset} =
               Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})

      assert errors_on(changeset).owner
    end

    test "delete_github_repository/1 removes the repository", %{app: app} do
      {:ok, repo} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})
      assert {:ok, _} = Integrations.delete_github_repository(repo.id)
      assert Integrations.list_github_repositories(app) == []

      assert Repo.get_by!(Activity, action: "github_repository.deleted", target_id: repo.id)
    end

    test "list_github_repositories/1 returns repos ordered by owner/repo", %{app: app} do
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "tuist"})
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "apple", repo: "swift"})

      repos = Integrations.list_github_repositories(app)
      assert [%{owner: "apple", repo: "swift"}, %{owner: "tuist", repo: "tuist"}] = repos
    end
  end
end
