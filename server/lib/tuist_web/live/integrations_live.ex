defmodule TuistWeb.IntegrationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Billing.Entitlements
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
    pending_or_installed = selected_account.github_app_installation
    # A row only counts as "installed" once GitHub has assigned an
    # installation_id via the post-install setup callback; manifest-flow
    # rows exist with credentials but `installation_id: nil` until then.
    github_installation =
      if pending_or_installed && pending_or_installed.installation_id, do: pending_or_installed

    slack_installation = selected_account.slack_installation
    vcs_connections = vcs_connections(selected_account)
    github_enterprise_available? = Entitlements.allows?(selected_account, :github_enterprise_server)

    # When github.com isn't configured (no `TUIST_GITHUB_APP_*` env
    # vars on the deployment) but the account is entitled to GHES,
    # default the UI to the Enterprise tab. Otherwise the github.com
    # tab is selected by default and its Install button generates a
    # broken `/apps//installations/new` URL until the user manually
    # switches tabs.
    default_to_enterprise? =
      github_enterprise_available? and not Tuist.Environment.github_app_configured?()

    socket =
      socket
      |> assign(selected_tab: "integrations")
      |> assign(selected_account: selected_account)
      |> assign(github_app_installation: github_installation)
      |> assign(slack_installation: slack_installation)
      |> assign(vcs_connections: vcs_connections)
      |> assign(selected_project_id: nil)
      |> assign(selected_repository_full_handle: nil)
      |> assign(github_client_url: if(default_to_enterprise?, do: "", else: VCS.default_client_url()))
      |> assign(github_client_url_error: nil)
      |> assign(show_github_enterprise_input: default_to_enterprise?)
      |> assign(github_enterprise_available?: github_enterprise_available?)
      |> assign(github_card_visible?: github_card_visible?(selected_account, github_installation))
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
  def handle_event("update-github-client-url", %{"github_client_url" => raw_url}, socket) do
    {url, error} = validate_github_client_url(raw_url, socket.assigns.show_github_enterprise_input)

    socket =
      socket
      |> assign(github_client_url: url)
      |> assign(github_client_url_error: error)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-github-com", _params, socket) do
    socket =
      socket
      |> assign(show_github_enterprise_input: false)
      |> assign(github_client_url: VCS.default_client_url())
      |> assign(github_client_url_error: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-github-enterprise", _params, socket) do
    if socket.assigns.github_enterprise_available? do
      socket =
        socket
        |> assign(show_github_enterprise_input: true)
        # Don't pre-fill with the default github.com URL — the user has
        # to enter their GHES base URL. Leaving it as the default would
        # let an Enterprise-tab Install button silently install the
        # github.com App, which is exactly the wrong target.
        |> assign(github_client_url: "")
        |> assign(github_client_url_error: nil)

      {:noreply, socket}
    else
      # Defense in depth: the tab is hidden in the UI for non-Enterprise
      # accounts, so reaching this branch implies a fabricated event.
      {:noreply, socket}
    end
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
    %{selected_account: selected_account, current_user: current_user} = assigns

    with {:ok, connection} <- Projects.get_vcs_connection(connection_id),
         connection = Tuist.Repo.preload(connection, project: [:account]),
         :ok <- Authorization.authorize(:account_update, current_user, connection.project.account) do
      {:ok, _} = Projects.delete_vcs_connection(connection)
      vcs_connections = vcs_connections(selected_account, force: true)
      {:noreply, assign(socket, vcs_connections: vcs_connections)}
    else
      _ -> {:noreply, socket}
    end
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

  # The Install button is disabled when:
  #   * The current URL has a validation error.
  #   * The Enterprise tab is showing and the URL is empty or still
  #     collapsed to the github.com default — clicking Install in that
  #     state would silently target github.com from inside the GHES tab.
  defp install_button_disabled?(assigns) do
    not is_nil(assigns.github_client_url_error) or
      (assigns.show_github_enterprise_input and
         (assigns.github_client_url in ["", nil] or
            assigns.github_client_url == VCS.default_client_url()))
  end

  defp validate_github_client_url(raw_url, enterprise_tab?) do
    trimmed = raw_url |> to_string() |> String.trim()

    cond do
      trimmed == "" and enterprise_tab? ->
        # On the Enterprise tab the URL is required and must not silently
        # collapse to the github.com default — that would let the Install
        # button target github.com from inside the GHES tab.
        {"", dgettext("dashboard_integrations", "Required")}

      trimmed == "" ->
        {VCS.default_client_url(), nil}

      enterprise_tab? and trimmed == VCS.default_client_url() ->
        {trimmed, dgettext("dashboard_integrations", "Use a GitHub Enterprise Server URL")}

      true ->
        case VCS.validate_client_url(trimmed) do
          {:ok, url} -> {url, nil}
          {:error, _} -> {trimmed, dgettext("dashboard_integrations", "Invalid URL")}
        end
    end
  end

  # The GitHub integration card is shown when ANY of:
  #   * The github.com Tuist App env vars are set (the hosted Tuist server
  #     always has them);
  #   * An installation already exists for the account (GHES install
  #     persisted via the manifest flow even with no env vars);
  #   * The account is entitled to GHES (so they can start the manifest
  #     flow without github.com env vars on a self-hosted Tuist).
  defp github_card_visible?(account, github_installation) do
    Tuist.Environment.github_app_configured?() or
      not is_nil(github_installation) or
      Entitlements.allows?(account, :github_enterprise_server)
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
