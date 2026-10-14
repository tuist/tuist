defmodule Tuist.OriginTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Origin
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    account = Repo.preload(user, :account).account

    remote = %{
      "id" => "inst-#{user.id}",
      "appId" => "app-tuist",
      "target" => %{"id" => "ns-#{user.id}", "slug" => "org"},
      "scopes" => []
    }

    pending = %{
      "installation_id" => remote["id"],
      "namespace_id" => remote["target"]["id"],
      "expires_at" => System.system_time(:second) + 300
    }

    stub(Environment, :origin_app_credentials, fn -> %{app_id: "app-tuist"} end)
    stub(Client, :get_installation, fn _ -> {:ok, remote} end)
    %{user: user, account: account, remote: remote, pending: pending}
  end

  test "confirmation rejects expired approval, unauthorized accounts and cross-account reuse", context do
    %{account: account, user: user, pending: pending} = context
    assert {:error, :expired_installation} = Origin.confirm(account, user, %{pending | "expires_at" => 0})
    assert {:ok, installation} = Origin.confirm(account, user, pending)
    assert installation.account_id == account.id
    other = Repo.preload(AccountsFixtures.user_fixture(), :account)
    assert {:error, _} = Origin.confirm(other.account, user, pending)
    assert {:error, :invalid_installation} = Origin.confirm(other.account, other, pending)
  end

  test "project connections require an account-owned project and an accessible native repository", %{
    account: account,
    user: user,
    pending: pending
  } do
    assert {:ok, _} = Origin.confirm(account, user, pending)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    other = ProjectsFixtures.project_fixture()
    repository = %{"id" => "repo-1", "fullName" => "org/repo", "defaultBranch" => "develop"}

    stub(Client, :repositories, fn _ ->
      {:ok, [repository, Map.merge(repository, %{"id" => "mirror", "mirror" => %{}})]}
    end)

    assert {:error, :repository_not_accessible} = Origin.connect_project(account, user, other.id, "repo-1")
    assert {:error, :repository_not_accessible} = Origin.connect_project(account, user, project.id, "mirror")
    assert {:ok, connection} = Origin.connect_project(account, user, project.id, "repo-1")
    assert connection.provider == :origin
    assert Projects.get_project_by_id(project.id).default_branch == "develop"
    assert Projects.projects_by_vcs_repository_full_handle("org/repo") == []

    assert Enum.map(Projects.projects_by_vcs_repository_full_handle("org/repo", provider: :origin), & &1.id) == [
             project.id
           ]

    assert {:error, _} = Origin.connect_project(account, user, project.id, "repo-1")
  end

  test "lifecycle events reconcile current state, repository renames, revocation and uninstall", %{
    account: account,
    user: user,
    pending: pending,
    remote: remote
  } do
    assert {:ok, installation} = Origin.confirm(account, user, pending)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    stub(Client, :repositories, fn _ -> {:ok, [%{"id" => "repo-1", "fullName" => "org/repo"}]} end)
    assert {:ok, connection} = Origin.connect_project(account, user, project.id, "repo-1")

    event = %{
      "appId" => "app-tuist",
      "installationId" => installation.installation_id,
      "event" => %{"type" => "installation.updated"}
    }

    stub(Client, :repositories, fn _ -> {:ok, [%{"id" => "repo-1", "fullName" => "renamed/repo"}]} end)
    assert :ok = Origin.handle_webhook(event)
    assert Repo.get(Projects.VCSConnection, connection.id).repository_full_handle == "renamed/repo"
    stub(Client, :get_installation, fn _ -> {:ok, Map.put(remote, "suspendedAt", "2026-10-14T00:00:00Z")} end)
    assert :ok = Origin.handle_webhook(event)
    assert Origin.installation_for_account(account.id).suspended
    stub(Client, :get_installation, fn _ -> {:ok, remote} end)
    stub(Client, :repositories, fn _ -> {:ok, []} end)
    assert :ok = Origin.handle_webhook(event)
    refute Repo.get(Projects.VCSConnection, connection.id)
    stub(Client, :get_installation, fn _ -> {:error, {:http, 404}} end)
    assert :ok = Origin.handle_webhook(event)
    refute Repo.get(Installation, installation.id)
  end
end
