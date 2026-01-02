defmodule TuistWeb.IntegrationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Slack
  alias Tuist.Utilities.DateFormatter
  alias Tuist.VCS

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_integrations", "You are not authorized to perform this action.")
    end

    selected_account = Tuist.Repo.preload(selected_account, [:github_app_installation, :slack_installation, :projects])
    github_installation = selected_account.github_app_installation
    slack_installation = selected_account.slack_installation
    vcs_connections = vcs_connections(selected_account)

    socket =
      socket
      |> assign(selected_tab: "integrations")
      |> assign(selected_account: selected_account)
      |> assign(github_app_installation: github_installation)
      |> assign(slack_installation: slack_installation)
      |> assign(vcs_connections: vcs_connections)
      |> assign(selected_project_id: nil)
      |> assign(selected_repository_full_handle: nil)
      |> assign(:head_title, "#{dgettext("dashboard_integrations", "Integrations")} · #{selected_account.name} · Tuist")
      |> then(fn socket ->
        if github_installation do
          assign_async(socket, :github_repositories, fn ->
            {:ok, repositories} = VCS.get_github_app_installation_repositories(github_installation)
            {:ok, %{github_repositories: repositories}}
          end)
        else
          assign(socket, github_repositories: %{ok?: true, result: [], loading: false})
        end
      end)

    {:ok, socket}
  end

  @impl true
  def handle_event("close-add-connection-modal", _params, socket) do
    socket = push_event(socket, "close-modal", %{id: "add-connection-modal"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-project", %{"project_id" => project_id}, socket) do
    {:noreply, assign(socket, selected_project_id: String.to_integer(project_id))}
  end

  @impl true
  def handle_event("select-repository", %{"repository" => repository_full_handle}, socket) do
    {:noreply, assign(socket, selected_repository_full_handle: repository_full_handle)}
  end

  @impl true
  def handle_event(
        "create-connection",
        _params,
        %{
          assigns:
            %{
              selected_repository_full_handle: repository_full_handle,
              selected_account: selected_account,
              current_user: current_user
            } = assigns
        } = socket
      ) do
    project = get_selected_project(assigns)
    project_id = if project, do: project.id

    attrs = %{
      project_id: project_id,
      provider: :github,
      repository_full_handle: repository_full_handle,
      created_by_id: current_user.id,
      github_app_installation_id: selected_account.github_app_installation.id
    }

    {:ok, _connection} = Projects.create_vcs_connection(attrs)
    vcs_connections = vcs_connections(selected_account, force: true)

    socket =
      socket
      |> assign(vcs_connections: vcs_connections)
      |> assign(selected_project_id: nil)
      |> assign(selected_repository_full_handle: nil)
      |> push_event("close-modal", %{id: "add-connection-modal"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete-connection", %{"connection_id" => connection_id}, %{assigns: assigns} = socket) do
    %{selected_account: selected_account} = assigns

    {:ok, connection} = Projects.get_vcs_connection(connection_id)
    {:ok, _} = Projects.delete_vcs_connection(connection)
    vcs_connections = vcs_connections(selected_account, force: true)

    socket = assign(socket, vcs_connections: vcs_connections)

    {:noreply, socket}
  end

  @impl true
  def handle_event("disconnect-slack", _params, %{assigns: assigns} = socket) do
    %{slack_installation: slack_installation} = assigns

    if slack_installation do
      {:ok, _} = Slack.delete_installation(slack_installation)
    end

    {:noreply, assign(socket, slack_installation: nil)}
  end

  defp get_available_projects(%{selected_account: selected_account, vcs_connections: vcs_connections}) do
    connected_project_ids = MapSet.new(vcs_connections, & &1.project_id)

    selected_account.projects
    |> Enum.reject(fn project -> MapSet.member?(connected_project_ids, project.id) end)
    |> Enum.sort_by(& &1.name, :asc)
  end

  defp get_available_repositories(%{github_repositories: github_repositories_async}) do
    repositories =
      if github_repositories_async.ok? do
        github_repositories_async.result
      else
        []
      end

    Enum.sort_by(repositories, & &1.full_name, :asc)
  end

  defp get_selected_project(assigns) do
    selected_id =
      case get_available_projects(assigns) do
        [single_project] when is_nil(assigns.selected_project_id) -> single_project.id
        _ -> assigns.selected_project_id
      end

    if selected_id do
      Enum.find(assigns.selected_account.projects, fn p -> p.id == selected_id end)
    end
  end

  defp get_connection_info(vcs_connection) do
    time_ago = DateFormatter.from_now(vcs_connection.inserted_at)

    if is_nil(vcs_connection.created_by) do
      dgettext("dashboard_integrations", "Connected %{time_ago}", time_ago: time_ago)
    else
      dgettext("dashboard_integrations", "Connected %{time_ago} by %{name}",
        time_ago: time_ago,
        name: vcs_connection.created_by.account.name
      )
    end
  end

  defp vcs_connections(account, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    account =
      Tuist.Repo.preload(
        account,
        [
          projects: [vcs_connection: [created_by: [:account], project: []]]
        ],
        force: force
      )

    account.projects
    |> Enum.filter(& &1.vcs_connection)
    |> Enum.map(& &1.vcs_connection)
  end
end
