defmodule TuistWeb.IntegrationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Utilities.DateFormatter

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            gettext("You are not authorized to perform this action.")
    end

    # Preload the github_app_installation
    selected_account = Tuist.Repo.preload(selected_account, :github_app_installation)

    # Get or check GitHub app installation if not already loaded
    github_installation =
      case selected_account.github_app_installation do
        nil ->
          case Projects.get_github_app_installation(selected_account) do
            {:ok, installation} -> installation
            {:error, _} -> nil
          end

        installation ->
          installation
      end

    # Get existing project connections for this account
    project_connections = Projects.list_account_project_connections(selected_account, preload: [:project, :created_by])

    socket =
      socket
      |> assign(selected_tab: "integrations")
      |> assign(selected_account: selected_account)
      |> assign(github_app_installation: github_installation)
      |> assign(project_connections: project_connections)
      |> assign(github_repositories: [])
      |> assign(selected_project_id: nil)
      |> assign(selected_repository: nil)
      |> assign(:head_title, "#{gettext("Integrations")} · #{selected_account.name} · Tuist")

    # If GitHub app is installed, fetch repositories
    socket =
      if github_installation do
        case Projects.get_github_repositories(github_installation) do
          {:ok, repositories} ->
            assign(socket, github_repositories: repositories)

          {:error, _} ->
            assign(socket, github_repositories: [])
        end
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("open-add-connection-modal", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("close-add-connection-modal", _params, socket) do
    socket = push_event(socket, "close-modal", %{id: "add-connection-modal"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("project-dropdown", %{"project_id" => project_id}, socket) when project_id != "" do
    {:noreply, assign(socket, selected_project_id: String.to_integer(project_id))}
  end

  @impl true
  def handle_event("project-dropdown", %{"project_id" => ""}, socket) do
    {:noreply, assign(socket, selected_project_id: nil)}
  end

  @impl true
  def handle_event("repository-dropdown", %{"repository" => repository_json}, socket) when repository_json != "" do
    repository = Jason.decode!(repository_json)
    {:noreply, assign(socket, selected_repository: repository)}
  end

  @impl true
  def handle_event("repository-dropdown", %{"repository" => ""}, socket) do
    {:noreply, assign(socket, selected_repository: nil)}
  end

  @impl true
  def handle_event("select-project", %{"project_id" => project_id}, socket) when project_id != "" do
    {:noreply, assign(socket, selected_project_id: String.to_integer(project_id))}
  end

  @impl true
  def handle_event("select-project", %{"project_id" => ""}, socket) do
    {:noreply, assign(socket, selected_project_id: nil)}
  end

  @impl true
  def handle_event("select-repository", %{"repository" => repository_json}, socket) when repository_json != "" do
    repository = Jason.decode!(repository_json)
    {:noreply, assign(socket, selected_repository: repository)}
  end

  @impl true
  def handle_event("select-repository", %{"repository" => ""}, socket) do
    {:noreply, assign(socket, selected_repository: nil)}
  end

  @impl true
  def handle_event("create-connection", _params, %{assigns: assigns} = socket) do
    %{
      selected_repository: repository,
      selected_account: selected_account,
      current_user: current_user
    } = assigns

    project_id = get_selected_project_id(assigns)

    if project_id && repository do
      attrs = %{
        project_id: project_id,
        provider: :github,
        external_id: Integer.to_string(repository["id"]),
        repository_full_handle: repository["full_name"],
        created_by_id: current_user.account.id
      }

      case Projects.create_project_connection(attrs) do
        {:ok, _connection} ->
          project_connections = Projects.list_account_project_connections(selected_account, preload: [:project, :created_by])

          socket =
            socket
            |> assign(project_connections: project_connections)
            |> assign(selected_project_id: nil)
            |> assign(selected_repository: nil)
            |> push_event("close-modal", %{id: "add-connection-modal"})

          {:noreply, socket}

        {:error, changeset} ->
          error_message =
            Enum.map_join(changeset.errors, ", ", fn {field, {message, _}} -> "#{field}: #{message}" end)

          socket = put_flash(socket, :error, gettext("Failed to create connection: %{error}", error: error_message))
          {:noreply, socket}
      end
    else
      socket = put_flash(socket, :error, gettext("Please select both a project and repository"))
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete-connection", %{"connection_id" => connection_id}, %{assigns: assigns} = socket) do
    %{selected_account: selected_account} = assigns

    case Projects.get_project_connection(connection_id) do
      nil ->
        socket = put_flash(socket, :error, gettext("Connection not found"))
        {:noreply, socket}

      connection ->
        case Projects.delete_project_connection(connection) do
          {:ok, _} ->
            project_connections = Projects.list_account_project_connections(selected_account, preload: [:project, :created_by])

            socket =
              socket
              |> assign(project_connections: project_connections)
              |> put_flash(:info, gettext("Project connection deleted successfully"))

            {:noreply, socket}

          {:error, _} ->
            socket = put_flash(socket, :error, gettext("Failed to delete connection"))
            {:noreply, socket}
        end
    end
  end

  # Helper functions

  defp get_account_projects(%{selected_account: selected_account}) do
    selected_account
    |> Projects.get_all_project_accounts()
    |> Enum.map(& &1.project)
  end

  defp get_available_projects(%{selected_account: selected_account, project_connections: project_connections}) do
    # Get all projects for the account
    all_projects = get_account_projects(%{selected_account: selected_account})
    
    # Filter out projects that are already connected
    connected_project_ids =
      project_connections
      |> Enum.map(& &1.project_id)
      |> MapSet.new()

    Enum.reject(all_projects, fn project -> MapSet.member?(connected_project_ids, project.id) end)
  end

  defp get_available_repositories(%{github_repositories: repositories, project_connections: project_connections}) do
    # Filter out repositories that are already connected through GitHub
    connected_repo_ids =
      project_connections
      |> Enum.filter(&(&1.provider == :github))
      |> Enum.map(& &1.external_id)
      |> MapSet.new(&String.to_integer/1)

    Enum.reject(repositories, fn repo -> MapSet.member?(connected_repo_ids, repo.id) end)
  end

  defp connection_exists?(project_connections, project_id, repository_id) do
    Enum.any?(project_connections, fn connection ->
      connection.project_id == project_id && connection.external_id == Integer.to_string(repository_id)
    end)
  end

  defp get_selected_project_id(assigns) do
    case get_available_projects(assigns) do
      [single_project] when is_nil(assigns.selected_project_id) -> single_project.id
      _ -> assigns.selected_project_id
    end
  end

  defp get_selected_project_name(assigns) do
    selected_id = get_selected_project_id(assigns)
    
    if selected_id do
      project = Enum.find(get_account_projects(assigns), fn p -> p.id == selected_id end)
      if project, do: project.name
    end
  end

  defp get_connection_info(project_connection) do
    time_ago = DateFormatter.from_now(project_connection.inserted_at)
    
    if is_nil(project_connection.created_by) do
      gettext("Connected %{time_ago}", time_ago: time_ago)
    else
      gettext("Connected %{time_ago} by %{name}", 
        time_ago: time_ago,
        name: project_connection.created_by.name
      )
    end
  end
end
