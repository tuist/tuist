defmodule Tuist.Migrations.BackfillVCSConnections do
  @moduledoc """
  Backfills vcs_connections table from legacy vcs_repository_full_handle and vcs_provider fields.

  This module:
  - Finds all projects with vcs_repository_full_handle
  - Groups them by account
  - Gets or creates GitHub app installation for each account
  - Creates VCSConnection records for projects with valid installations
  """

  import Ecto.Query

  alias Tuist.GitHub.App
  alias Tuist.GitHubAppInstallations
  alias Tuist.GitHubAppInstallations.GitHubAppInstallation
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo

  require Logger

  @doc """
  Run the migration to backfill VCS connections.

  Returns:
    {:ok, %{created: count, skipped: count, installations_created: count}}
  """
  def run do
    Logger.info("Starting backfill of project connections...")

    results = %{created: 0, skipped: 0, installations_created: 0}

    # Get all projects with vcs_repository_full_handle
    projects_with_vcs =
      Repo.all(
        from(p in Project,
          where: not is_nil(p.vcs_repository_full_handle) and p.vcs_repository_full_handle != "",
          preload: [:account]
        )
      )

    Logger.info("Found #{length(projects_with_vcs)} projects with VCS repository handles")

    projects_by_account = Enum.group_by(projects_with_vcs, & &1.account)

    results =
      Enum.reduce(projects_by_account, results, fn {account, projects}, acc ->
        process_account_projects(account, projects, acc)
      end)

    Logger.info("""
    Backfill completed:
    - Created: #{results.created} connections
    - GitHub app installations created: #{results.installations_created}
    - Skipped: #{results.skipped} projects
    """)

    {:ok, results}
  end

  defp process_account_projects(account, projects, results) do
    Logger.info("Processing #{length(projects)} projects for account #{account.name}")

    {:ok, github_app_installation, created?} =
      get_or_create_github_app_installation(account)

    results = if created?, do: %{results | installations_created: results.installations_created + 1}, else: results

    Logger.info("Using GitHub app installation for #{account.name}")

    Enum.reduce(projects, results, fn project, acc ->
      create_connection_for_project(project, github_app_installation, acc)
    end)
  end

  defp get_or_create_github_app_installation(account) do
    case Repo.one(from gi in GitHubAppInstallation, where: gi.account_id == ^account.id) do
      nil ->
        {:ok, installation} =
          App.get_organization_installation(account.name)

        attrs = %{
          account_id: account.id,
          installation_id: Integer.to_string(installation["id"])
        }

        {:ok, github_installation} =
          GitHubAppInstallations.create(attrs)

        Logger.info("Created GitHub app installation record for #{account.name}")
        {:ok, github_installation, true}

      existing_installation ->
        {:ok, existing_installation, false}
    end
  end

  defp create_connection_for_project(project, github_app_installation, results) do
    external_id = project.vcs_repository_full_handle

    existing_connection_query =
      from(pc in VCSConnection,
        where:
          pc.project_id == ^project.id and
            pc.provider == :github and
            pc.repository_full_handle == ^project.vcs_repository_full_handle
      )

    case Repo.one(existing_connection_query) do
      nil ->
        attrs = %{
          project_id: project.id,
          provider: :github,
          external_id: external_id,
          repository_full_handle: project.vcs_repository_full_handle,
          created_by_id: nil,
          github_app_installation_id: github_app_installation.id
        }

        {:ok, _connection} =
          Projects.create_vcs_connection(attrs)

        Logger.info("Created connection for project #{project.name} -> #{project.vcs_repository_full_handle}")
        %{results | created: results.created + 1}

      _existing ->
        Logger.info("Connection already exists for project #{project.name}")
        %{results | skipped: results.skipped + 1}
    end
  end
end
