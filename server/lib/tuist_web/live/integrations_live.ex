defmodule TuistWeb.IntegrationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Billing.Entitlements
  alias Tuist.FeatureFlags
  alias Tuist.Projects
  alias Tuist.Runners.Buildkite
  alias Tuist.Utilities.DateFormatter
  alias Tuist.VCS

  # The fields the Buildkite modal renders an input for.
  @buildkite_form_fields [:organization_slug, :agent_token]

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_integrations", "You are not authorized to perform this action.")
    end

    selected_account = Tuist.Repo.preload(selected_account, [:github_app_installation, :projects])
    pending_or_installed = selected_account.github_app_installation
    # A row only counts as "installed" once GitHub has assigned an
    # installation_id via the post-install setup callback; manifest-flow
    # rows exist with credentials but `installation_id: nil` until then.
    github_installation =
      if pending_or_installed && pending_or_installed.installation_id, do: pending_or_installed

    vcs_connections = vcs_connections(selected_account)
    github_enterprise_available? = Entitlements.allows?(selected_account, :github_enterprise_server)
    github_app_configured? = Tuist.Environment.github_app_configured?()

    # When github.com isn't configured (no `TUIST_GITHUB_APP_*` env
    # vars on the deployment) but the account is entitled to GHES,
    # default the UI to the Enterprise tab.
    default_to_enterprise? = github_enterprise_available? and not github_app_configured?

    socket =
      socket
      |> assign(selected_account: selected_account)
      |> assign(github_app_installation: github_installation)
      |> assign(vcs_connections: vcs_connections)
      |> assign(selected_project_id: nil)
      |> assign(selected_repository_full_handle: nil)
      |> assign(github_client_url: if(default_to_enterprise?, do: "", else: VCS.default_client_url()))
      |> assign(github_client_url_error: nil)
      |> assign(github_app_owner: "")
      |> assign(github_app_owner_error: nil)
      |> assign(show_github_enterprise_input: default_to_enterprise?)
      |> assign(github_enterprise_available?: github_enterprise_available?)
      |> assign(github_app_configured?: github_app_configured?)
      |> assign(github_card_visible?: github_card_visible?(selected_account, github_installation))
      |> assign(buildkite_card_visible?: FeatureFlags.runners_enabled?(selected_account))
      |> assign(buildkite_field_errors: %{})
      |> assign(buildkite_form_error: nil)
      |> assign(buildkite_flash: nil)
      |> assign(buildkite_has_changes: false)
      |> assign_buildkite_installation()
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
  def handle_event("close-connect-buildkite-modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "connect-buildkite-modal"})}
  end

  @impl true
  def handle_event("connect-buildkite", params, %{assigns: %{selected_account: account}} = socket) do
    # Only what the modal showed: the slug and the token on first connect,
    # the token alone afterwards (the slug is edited on the card). The
    # stack key identifies this controller to Buildkite and scopes its
    # reservations, so it is derived from the account rather than typed: a
    # customer-chosen key that collided with another account's would hand
    # them each other's reservations.
    attrs =
      params
      |> Map.take(["organization_slug", "agent_token"])
      |> Map.new(fn {field, value} -> {String.to_existing_atom(field), String.trim(value)} end)
      |> Map.put(:stack_key, "tuist-#{account.id}")

    case Buildkite.upsert_installation(account.id, attrs) do
      {:ok, _installation} ->
        {:noreply,
         socket
         |> assign(buildkite_field_errors: %{}, buildkite_form_error: nil)
         |> assign_buildkite_installation()
         |> push_event("close-modal", %{id: "connect-buildkite-modal"})}

      {:error, changeset} ->
        {field_errors, form_error} = split_buildkite_errors(changeset)

        {:noreply, assign(socket, buildkite_field_errors: field_errors, buildkite_form_error: form_error)}
    end
  end

  @impl true
  def handle_event("validate-buildkite", params, %{assigns: %{buildkite_installation: installation}} = socket) do
    values = Map.merge(socket.assigns.buildkite_form_values, Map.take(params, ["organization_slug", "agent_token"]))

    has_changes =
      String.trim(values["organization_slug"]) != installation.organization_slug or
        String.trim(values["agent_token"]) != ""

    {:noreply, assign(socket, buildkite_form_values: values, buildkite_has_changes: has_changes, buildkite_flash: nil)}
  end

  @impl true
  def handle_event("save-buildkite", params, %{assigns: %{selected_account: account}} = socket) do
    token = params |> Map.get("agent_token", "") |> String.trim()
    attrs = %{organization_slug: params |> Map.get("organization_slug", "") |> String.trim()}

    # A blank token keeps the current one: it is never shown again, so
    # there is nothing for the customer to re-enter.
    attrs = if token == "", do: attrs, else: Map.put(attrs, :agent_token, token)

    case Buildkite.upsert_installation(account.id, attrs) do
      {:ok, _installation} ->
        {:noreply,
         socket
         |> assign(buildkite_field_errors: %{})
         |> assign(buildkite_flash: {"success", dgettext("dashboard_integrations", "Buildkite connection saved.")})
         |> assign_buildkite_installation()}

      {:error, changeset} ->
        {field_errors, form_error} = split_buildkite_errors(changeset)

        {:noreply,
         assign(socket,
           buildkite_field_errors: field_errors,
           buildkite_flash: if(form_error, do: {"error", form_error}),
           buildkite_form_values: Map.take(params, ["organization_slug", "agent_token"])
         )}
    end
  end

  @impl true
  def handle_event("disconnect-buildkite", _params, %{assigns: %{selected_account: account}} = socket) do
    :ok = Buildkite.delete_installation(account.id)

    {:noreply,
     socket
     |> assign(buildkite_field_errors: %{}, buildkite_form_error: nil, buildkite_flash: nil)
     |> assign_buildkite_installation()}
  end

  @impl true
  def handle_event("update-github-client-url", params, socket) do
    raw_url = Map.get(params, "github_client_url", socket.assigns.github_client_url)
    raw_owner = Map.get(params, "github_app_owner", socket.assigns.github_app_owner)
    {url, error} = validate_github_client_url(raw_url, socket.assigns.show_github_enterprise_input)
    {github_app_owner, github_app_owner_error} = validate_github_app_owner(raw_owner)

    socket =
      socket
      |> assign(github_client_url: url)
      |> assign(github_client_url_error: error)
      |> assign(github_app_owner: github_app_owner)
      |> assign(github_app_owner_error: github_app_owner_error)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-github-com", _params, socket) do
    socket =
      socket
      |> assign(show_github_enterprise_input: false)
      |> assign(github_client_url: VCS.default_client_url())
      |> assign(github_client_url_error: nil)
      |> assign(github_app_owner: "")
      |> assign(github_app_owner_error: nil)

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
        |> assign(github_app_owner: "")
        |> assign(github_app_owner_error: nil)

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
    sync_default_branch(project, repository_full_handle, assigns)
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

  # When a project is connected to a GitHub repository, adopt the
  # repository's default branch as the project's baseline branch. The
  # repository list is already loaded with `default_branch`, so this is a
  # free metadata copy with no extra GitHub call. Only the initial
  # connection syncs; a later manual edit in project settings is preserved.
  defp sync_default_branch(nil, _repository_full_handle, _assigns), do: :ok

  defp sync_default_branch(project, repository_full_handle, assigns) do
    repository =
      assigns
      |> get_available_repositories()
      |> Enum.find(&(&1.full_name == repository_full_handle))

    case repository do
      %{default_branch: default_branch} when is_binary(default_branch) and default_branch != "" ->
        Projects.update_project(project, %{default_branch: default_branch})

      _ ->
        :ok
    end
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
  #     collapsed to the github.com default. Clicking Install in that
  #     state would silently target github.com from inside the GHES tab.
  #   * The github.com tab is showing but the deployment has no
  #     github.com App configured. The install URL embeds
  #     `TUIST_GITHUB_APP_NAME`, so without it the button sends the user
  #     to `https://github.com/apps//installations/new`, which 404s.
  defp install_button_disabled?(assigns) do
    not is_nil(assigns.github_client_url_error) or
      not is_nil(assigns.github_app_owner_error) or
      (assigns.show_github_enterprise_input and
         (assigns.github_client_url in ["", nil] or
            assigns.github_client_url == VCS.default_client_url())) or
      (not assigns.show_github_enterprise_input and not assigns.github_app_configured?)
  end

  defp validate_github_client_url(raw_url, enterprise_tab?) do
    trimmed = raw_url |> to_string() |> String.trim()

    cond do
      trimmed == "" ->
        validate_empty_github_client_url(enterprise_tab?)

      enterprise_tab? and github_com_url?(trimmed) ->
        {trimmed, dgettext("dashboard_integrations", "Use a GitHub Enterprise Server URL")}

      true ->
        validate_non_empty_github_client_url(trimmed, enterprise_tab?)
    end
  end

  defp validate_empty_github_client_url(true) do
    # On the Enterprise tab the URL is required and must not silently
    # collapse to the github.com default — that would let the Install
    # button target github.com from inside the GHES tab.
    {"", dgettext("dashboard_integrations", "Required")}
  end

  defp validate_empty_github_client_url(false) do
    {VCS.default_client_url(), nil}
  end

  defp validate_non_empty_github_client_url(trimmed, enterprise_tab?) do
    case VCS.validate_client_url(trimmed) do
      {:ok, url} ->
        validate_enterprise_github_client_url(url, enterprise_tab?)

      {:error, _} ->
        {trimmed, dgettext("dashboard_integrations", "Invalid URL")}
    end
  end

  defp validate_enterprise_github_client_url(url, true) do
    if github_enterprise_base_url?(url) do
      {url, nil}
    else
      {url, dgettext("dashboard_integrations", "Use a GitHub Enterprise Server URL")}
    end
  end

  defp validate_enterprise_github_client_url(url, false) do
    {url, nil}
  end

  defp validate_github_app_owner(raw_owner) do
    trimmed = raw_owner |> to_string() |> String.trim()

    cond do
      trimmed == "" ->
        {"", nil}

      Regex.match?(~r/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/, trimmed) ->
        {trimmed, nil}

      true ->
        {trimmed, dgettext("dashboard_integrations", "Invalid organization")}
    end
  end

  defp github_com_url?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "github.com"} -> true
      _ -> false
    end
  end

  defp github_enterprise_base_url?(url) do
    case URI.parse(url) do
      %URI{host: host, path: path, query: nil, fragment: nil} when is_binary(host) ->
        path in [nil, "", "/"]

      _ ->
        false
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

  # Rendered on both sides of the connected/not-connected split, so the
  # header is defined once.
  defp buildkite_header(assigns) do
    ~H"""
    <div data-part="header">
      <span data-part="title">{dgettext("dashboard_integrations", "Buildkite")}</span>
      <span data-part="subtitle">
        {dgettext(
          "dashboard_integrations",
          "Run Buildkite jobs on Tuist runners. Tuist watches the self-hosted queues in your cluster and runs what it finds there."
        )}
      </span>
    </div>
    """
  end

  defp assign_buildkite_installation(%{assigns: %{selected_account: account}} = socket) do
    installation = Buildkite.get_installation(account.id)

    socket
    |> assign(buildkite_installation: installation)
    |> assign(buildkite_has_changes: false)
    |> assign(
      buildkite_form_values: %{
        "organization_slug" => (installation && installation.organization_slug) || "",
        "agent_token" => ""
      }
    )
  end

  # Errors land on the input that caused them. `stack_key` is derived, not
  # typed, so it has no input to attach to and would be invisible as a
  # field error; it becomes a banner instead.
  defp split_buildkite_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Regex.replace(~r/%\{(\w+)\}/, message, fn _whole, key ->
          opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
        end)
      end)

    {shown, hidden} = Enum.split_with(errors, fn {field, _} -> field in @buildkite_form_fields end)

    field_errors = Map.new(shown, fn {field, messages} -> {Atom.to_string(field), List.first(messages)} end)

    form_error =
      hidden
      |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
      |> List.first()

    {field_errors, form_error}
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
