defmodule TuistTestSupport.Fixtures.ProjectsFixtures do
  @moduledoc false

  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.VCS

  def project_fixture(opts \\ []) do
    account_id =
      cond do
        Keyword.has_key?(opts, :account) ->
          Keyword.get(opts, :account).id

        Keyword.has_key?(opts, :account_id) ->
          Keyword.get(opts, :account_id)

        true ->
          organization_id = TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture().id

          Repo.get_by!(Tuist.Accounts.Account,
            organization_id: organization_id
          ).id
      end

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
        build_system: Keyword.get(opts, :build_system, :xcode),
        preload: preload
      )
      |> Repo.preload(Keyword.get(opts, :preload, []))

    # Production create_project! seeds a default "Flaky test detection" alert
    # on every project. Most tests want a clean-slate project and assert on
    # explicitly created alerts, so the fixture strips the default by default.
    # Pass `with_default_alert: true` to opt in when you need the realistic
    # shape.
    if !Keyword.get(opts, :with_default_alert, false) do
      import Ecto.Query

      Repo.delete_all(
        from a in Tuist.Automations.Alerts.Alert,
          where: a.project_id == ^project.id
      )
    end

    if vcs_connection_opts do
      account = Repo.preload(project, :account).account

      repository_full_handle = Keyword.get(vcs_connection_opts, :repository_full_handle, "tuist/tuist")
      provider = Keyword.get(vcs_connection_opts, :provider, :github)

      github_app_installation =
        case Repo.get_by(Tuist.VCS.GitHubAppInstallation, account_id: account.id) do
          nil ->
            # Use a unique installation_id based on account_id to avoid conflicts
            installation_id = "#{account.id}12345"

            {:ok, installation} =
              VCS.create_github_app_installation(%{
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
