defmodule Atlas.Integrations.GitHubAppBootstrapTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Integrations.GitHubApp
  alias Atlas.Integrations.GitHubAppBootstrap
  alias Atlas.Integrations.GitHubRepository
  alias Atlas.Repo

  setup :verify_on_exit!

  test "upserts the configured GitHub App and monitored repository" do
    assert :ok = GitHubAppBootstrap.ensure_configured(github_app_config())

    app = Repo.get_by!(GitHubApp, app_id: "3700470")
    assert app.name == "tuist-atlas"
    assert app.installation_id == "123456"

    assert %GitHubRepository{github_app_id: github_app_id} =
             Repo.get_by(GitHubRepository, owner: "tuist", repo: "tuist")

    assert github_app_id == app.id
  end

  test "looks up the GitHub App installation when installation_id is not configured" do
    GitHubAPI
    |> expect(:find_installation_id, fn %GitHubApp{} = app, "tuist" ->
      assert app.app_id == "3700470"
      assert app.private_key == private_key()

      {:ok, "456789"}
    end)

    config =
      github_app_config()
      |> Keyword.delete(:installation_id)

    assert :ok = GitHubAppBootstrap.ensure_configured(config)

    app = Repo.get_by!(GitHubApp, app_id: "3700470")
    assert app.installation_id == "456789"
    assert Repo.get_by(GitHubRepository, owner: "tuist", repo: "tuist", github_app_id: app.id)
  end

  test "returns the installation lookup error without persisting app configuration" do
    GitHubAPI
    |> expect(:find_installation_id, fn %GitHubApp{} = app, "tuist" ->
      assert app.app_id == "3700470"

      {:error, :github_app_installation_not_found}
    end)

    config =
      github_app_config()
      |> Keyword.delete(:installation_id)

    assert {:error, :github_app_installation_not_found} = GitHubAppBootstrap.ensure_configured(config)
    refute Repo.get_by(GitHubApp, app_id: "3700470")
    refute Repo.get_by(GitHubRepository, owner: "tuist", repo: "tuist")
  end

  test "does not reassign a matching repository from another GitHub App" do
    other_app =
      %GitHubApp{}
      |> GitHubApp.changeset(%{
        name: "other-app",
        app_id: "12345",
        private_key: private_key(),
        webhook_secret: "whsec_other",
        installation_id: "98765"
      })
      |> Repo.insert!()

    other_repository =
      %GitHubRepository{}
      |> GitHubRepository.changeset(%{
        owner: "tuist",
        repo: "tuist",
        github_app_id: other_app.id
      })
      |> Repo.insert!()

    assert :ok = GitHubAppBootstrap.ensure_configured(github_app_config())

    app = Repo.get_by!(GitHubApp, app_id: "3700470")
    reloaded_other_repository = Repo.get!(GitHubRepository, other_repository.id)

    assert reloaded_other_repository.github_app_id == other_app.id
    assert Repo.get_by(GitHubRepository, owner: "tuist", repo: "tuist", github_app_id: app.id)
  end

  defp github_app_config do
    [
      name: "tuist-atlas",
      app_id: "3700470",
      private_key: private_key(),
      webhook_secret: "whsec_test",
      installation_id: "123456",
      owner: "tuist",
      repo: "tuist"
    ]
  end

  defp private_key, do: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----"
end
