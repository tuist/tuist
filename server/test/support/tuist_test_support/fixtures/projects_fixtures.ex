defmodule TuistTestSupport.Fixtures.ProjectsFixtures do
  @moduledoc false

  alias Tuist.GitHubAppInstallations
  alias Tuist.Projects
  alias Tuist.Repo

  def project_fixture(opts \\ []) do
    account_id =
      Keyword.get_lazy(opts, :account_id, fn ->
        organization_id = TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture().id

        Repo.get_by!(Tuist.Accounts.Account,
          organization_id: organization_id
        ).id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())
    preload = Keyword.get(opts, :preload, [:account])

    vcs_connection_opts = Keyword.get(opts, :vcs_connection)

    project =
      %{
        name: name,
        account: %{id: account_id}
      }
      |> Projects.create_project!(
        created_at: created_at,
        visibility: Keyword.get(opts, :visibility, :private),
        default_previews_visibility: Keyword.get(opts, :default_previews_visibility, :private),
        preload: preload
      )
      |> Repo.preload(Keyword.get(opts, :preload, []))

    if vcs_connection_opts do
      account = Repo.preload(project, :account).account

      repository_full_handle = Keyword.get(vcs_connection_opts, :repository_full_handle, "tuist/tuist")
      provider = Keyword.get(vcs_connection_opts, :provider, :github)

      github_app_installation =
        case Repo.get_by(Tuist.GitHubAppInstallations.GitHubAppInstallation, account_id: account.id) do
          nil ->
            # Use a unique installation_id based on account_id to avoid conflicts
            installation_id = "#{account.id}12345"

            {:ok, installation} =
              GitHubAppInstallations.create(%{
                account_id: account.id,
                installation_id: installation_id
              })

            installation

          existing ->
            existing
        end

      {:ok, _connection} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: provider,
          repository_full_handle: repository_full_handle,
          github_app_installation_id: github_app_installation.id
        })

      Repo.preload(project, :vcs_connection, force: true)
    else
      project
    end
  end
end
