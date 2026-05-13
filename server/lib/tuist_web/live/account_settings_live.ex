defmodule TuistWeb.AccountSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Phoenix.HTML.Form
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Locale, as: SharedLocale

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    rename_account_form = to_form(Account.update_changeset(selected_account, %{}))
    delete_organization_form = to_form(%{"name" => ""})
    delete_user_form = to_form(%{"name" => ""})
    region_form = to_form(Account.update_changeset(selected_account, %{region: Atom.to_string(selected_account.region)}))
    add_cache_endpoint_form = to_form(AccountCacheEndpoint.create_changeset(%{}))
    cache_endpoints = Accounts.list_account_cache_endpoints(selected_account)
    custom_cache_endpoints_available = Accounts.custom_cache_endpoints_available?(selected_account)
    kura_enabled = kura_enabled?(selected_account)
    if connected?(socket) and kura_enabled, do: Kura.subscribe_to_account(selected_account.id)

    preferred_locale_form =
      to_form(%{"preferred_locale" => current_user.preferred_locale || "browser"})

    socket =
      socket
      |> assign(selected_tab: "settings")
      |> assign(rename_account_form: rename_account_form)
      |> assign(delete_organization_form: delete_organization_form)
      |> assign(delete_user_form: delete_user_form)
      |> assign(region_form: region_form)
      |> assign(add_cache_endpoint_form: add_cache_endpoint_form)
      |> assign(cache_endpoints: cache_endpoints)
      |> assign(custom_cache_endpoints_available: custom_cache_endpoints_available)
      |> assign(kura_enabled: kura_enabled)
      |> assign(preferred_locale_form: preferred_locale_form)
      |> assign(:head_title, "#{dgettext("dashboard_account", "Settings")} · #{selected_account.name} · Tuist")
      |> load_kura_state()

    {:ok, socket}
  end

  @impl true
  def handle_event("rename_account", params, %{assigns: %{selected_account: selected_account}} = socket) do
    %{"account" => %{"name" => name}} = params

    case Accounts.update_account(selected_account, %{name: name}) do
      {:ok, account} ->
        socket = push_navigate(socket, to: ~p"/#{account.name}/settings")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, rename_account_form: to_form(changeset))}

      _error ->
        {:noreply, socket}
    end
  end

  def handle_event("close-rename-organization-modal", _, socket) do
    socket = push_event(socket, "close-modal", %{id: "rename-organization-modal"})

    {:noreply, socket}
  end

  def handle_event("delete_organization", %{"name" => name} = _params, %{assigns: %{selected_account: account}} = socket) do
    socket =
      if name == account.name do
        {:ok, organization} = Accounts.get_organization_by_id(account.organization_id)

        Accounts.delete_organization!(organization)

        push_navigate(socket, to: ~p"/")
      else
        assign(socket, delete_organization_form: to_form(%{"name" => ""}))
      end

    {:noreply, socket}
  end

  def handle_event("close-delete-organization-modal", _, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "delete-organization-modal"})
      |> assign(delete_organization_form: to_form(%{"name" => ""}))

    {:noreply, socket}
  end

  def handle_event("close-rename-account-modal", _, socket) do
    socket = push_event(socket, "close-modal", %{id: "rename-account-modal"})

    {:noreply, socket}
  end

  def handle_event("delete_user", %{"name" => name} = _params, %{assigns: %{selected_account: account}} = socket) do
    socket =
      if name == account.name do
        user = Accounts.get_user_by_id(account.user_id)

        Accounts.delete_user(user)

        push_navigate(socket, to: ~p"/")
      else
        assign(socket, delete_user_form: to_form(%{"name" => ""}))
      end

    {:noreply, socket}
  end

  def handle_event("close-delete-user-modal", _, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "delete-user-modal"})
      |> assign(delete_user_form: to_form(%{"name" => ""}))

    {:noreply, socket}
  end

  def handle_event(
        "select_preferred_locale",
        %{"value" => [value]},
        %{assigns: %{current_user: current_user, selected_account: selected_account}} = socket
      ) do
    preferred_locale = if value == "browser", do: nil, else: value

    {:ok, _user} = Accounts.update_user_preferred_locale(current_user, preferred_locale)

    {:noreply, push_navigate(socket, to: ~p"/#{selected_account.name}/settings")}
  end

  def handle_event("select_region", %{"value" => [value]}, %{assigns: %{selected_account: selected_account}} = socket) do
    region = if is_atom(value), do: value, else: String.to_existing_atom(value)

    {:ok, account} = Accounts.update_account(selected_account, %{region: region})
    region_form = to_form(Account.update_changeset(account, %{region: Atom.to_string(account.region)}))

    socket =
      socket
      |> assign(selected_account: account)
      |> assign(region_form: region_form)

    {:noreply, socket}
  end

  def handle_event(
        "create_cache_endpoint",
        %{"account_cache_endpoint" => %{"url" => url}},
        %{assigns: %{selected_account: selected_account}} = socket
      ) do
    case Accounts.create_account_cache_endpoint(selected_account, %{url: url}) do
      {:ok, _endpoint} ->
        cache_endpoints = Accounts.list_account_cache_endpoints(selected_account)
        add_cache_endpoint_form = to_form(AccountCacheEndpoint.create_changeset(%{}))

        socket =
          socket
          |> assign(cache_endpoints: cache_endpoints)
          |> assign(add_cache_endpoint_form: add_cache_endpoint_form)
          |> push_event("close-modal", %{id: "add-cache-endpoint-modal"})

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, add_cache_endpoint_form: to_form(changeset))}
    end
  end

  def handle_event("delete_cache_endpoint", %{"id" => endpoint_id}, socket) do
    case delete_cache_endpoint(socket, endpoint_id) do
      {:ok, cache_endpoints} ->
        {:noreply, assign(socket, cache_endpoints: cache_endpoints)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_delete_last_cache_endpoint", %{"id" => endpoint_id}, socket) do
    case delete_cache_endpoint(socket, endpoint_id) do
      {:ok, cache_endpoints} ->
        socket =
          socket
          |> assign(cache_endpoints: cache_endpoints)
          |> push_event("close-modal", %{id: "delete-endpoint-#{endpoint_id}-modal"})

        {:noreply, socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("close-delete-endpoint-modal-" <> endpoint_id, _, socket) do
    socket = push_event(socket, "close-modal", %{id: "delete-endpoint-#{endpoint_id}-modal"})

    {:noreply, socket}
  end

  def handle_event("close-add-cache-endpoint-modal", _, socket) do
    add_cache_endpoint_form = to_form(AccountCacheEndpoint.create_changeset(%{}))

    socket =
      socket
      |> push_event("close-modal", %{id: "add-cache-endpoint-modal"})
      |> assign(add_cache_endpoint_form: add_cache_endpoint_form)

    {:noreply, socket}
  end

  def handle_event("open-add-kura-server", _params, socket) do
    {:noreply, push_event(socket, "open-modal", %{id: "add-kura-server-modal"})}
  end

  def handle_event("close-add-kura-server-modal", _params, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "add-kura-server-modal"})
      |> assign(:add_kura_server_form, default_kura_server_form(socket.assigns.available_kura_regions))

    {:noreply, socket}
  end

  def handle_event("create_kura_server", params, %{assigns: %{kura_enabled: true}} = socket) do
    case {kura_region_from_params(params, socket.assigns.available_kura_regions), socket.assigns.latest_kura_version} do
      {nil, _} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("dashboard_account", "Select a Kura region before deploying."))
         |> push_event("close-modal", %{id: "add-kura-server-modal"})}

      {_region, nil} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext(
             "dashboard_account",
             "No Kura runtime image is configured right now. Try again after the next server deploy."
           )
         )
         |> push_event("close-modal", %{id: "add-kura-server-modal"})}

      {region, version} ->
        attrs = %{
          account_id: socket.assigns.selected_account.id,
          region: region,
          image_tag: kura_version_image_tag(version)
        }

        create_kura_server(socket, attrs)
    end
  end

  def handle_event("create_kura_server", _params, socket), do: {:noreply, socket}

  def handle_event("destroy_kura_server", %{"id" => id}, %{assigns: %{kura_enabled: true}} = socket) do
    case Kura.get_server(socket.assigns.selected_account.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_account", "Kura server not found."))}

      %Server{} = server ->
        {:ok, _} = Kura.destroy_server(server)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_account", "Destroying Kura server..."))
         |> load_kura_state()}
    end
  end

  def handle_event("destroy_kura_server", _params, socket), do: {:noreply, socket}

  def handle_event("retry_kura_server", %{"id" => id}, %{assigns: %{kura_enabled: true}} = socket) do
    with %Server{} = server <- Kura.get_server(socket.assigns.selected_account.id, id),
         version when not is_nil(version) <- socket.assigns.latest_kura_version,
         {:ok, _} <- Kura.retry_server(server, kura_version_image_tag(version)) do
      {:noreply, load_kura_state(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("retry_kura_server", _params, socket), do: {:noreply, socket}

  def handle_event(
        "toggle_custom_cache_endpoints",
        %{"checked" => checked},
        %{assigns: %{selected_account: selected_account}} = socket
      ) do
    {:ok, updated_account} =
      Accounts.update_account(selected_account, %{custom_cache_endpoints_enabled: checked})

    {:noreply, assign(socket, selected_account: updated_account)}
  end

  @impl true
  def handle_info({:kura_server, _event, _server}, %{assigns: %{kura_enabled: true}} = socket) do
    {:noreply, load_kura_state(socket)}
  end

  def handle_info({:kura_server, _event, _server}, socket), do: {:noreply, socket}

  defp load_kura_state(%{assigns: %{kura_enabled: false}} = socket) do
    socket
    |> assign(:kura_servers, [])
    |> assign(:kura_regions, [])
    |> assign(:available_kura_regions, [])
    |> assign(:latest_kura_version, nil)
    |> assign(:kura_global_endpoint_url, nil)
    |> assign(:add_kura_server_form, default_kura_server_form([]))
  end

  defp load_kura_state(socket, opts \\ []) do
    account = socket.assigns.selected_account
    servers = Kura.list_servers_for_account(account.id)
    regions = Regions.available()
    available_regions = available_kura_regions(regions, servers)
    latest = Keyword.get_lazy(opts, :latest_kura_version, fn -> List.first(Kura.latest_versions(1)) end)

    socket
    |> assign(:kura_servers, servers)
    |> assign(:kura_regions, regions)
    |> assign(:available_kura_regions, available_regions)
    |> assign(:latest_kura_version, latest)
    |> assign(:kura_global_endpoint_url, Kura.global_cache_endpoint_url(account))
    |> assign(:add_kura_server_form, default_kura_server_form(available_regions))
  end

  defp kura_enabled?(account) do
    Environment.dev?() or FunWithFlags.enabled?(:kura, for: account)
  end

  defp available_kura_regions(regions, servers) do
    occupied_regions = MapSet.new(servers, & &1.region)
    Enum.reject(regions, &MapSet.member?(occupied_regions, &1.id))
  end

  defp kura_region_from_params(params, available_regions) do
    [
      get_in(params, ["server", "region"]),
      params["region"]
    ]
    |> Enum.find(&present?/1)
    |> case do
      nil -> single_available_kura_region_id(available_regions)
      region -> region
    end
  end

  defp single_available_kura_region_id([region]), do: region.id
  defp single_available_kura_region_id(_regions), do: nil

  defp kura_version_image_tag(%{image_tag: image_tag}), do: image_tag
  defp kura_version_image_tag(%{version: "kura@" <> image_tag}), do: image_tag
  defp kura_version_image_tag(%{version: image_tag}), do: image_tag

  defp present?(value), do: is_binary(value) and value != ""

  defp default_kura_server_form([]), do: to_form(%{"region" => nil}, as: :server)

  defp default_kura_server_form([region | _]) do
    to_form(%{"region" => region.id}, as: :server)
  end

  defp create_kura_server(socket, attrs) do
    case Kura.create_server(attrs) do
      {:ok, server} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("dashboard_account", "Deploying Kura in %{region}...", region: server.region)
         )
         |> push_event("close-modal", %{id: "add-kura-server-modal"})
         |> load_kura_state(latest_kura_version: socket.assigns.latest_kura_version)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_account", "Failed to deploy Kura: %{reason}", reason: format_errors(changeset))
         )
         |> push_event("close-modal", %{id: "add-kura-server-modal"})}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_account", "Failed to deploy Kura: %{reason}", reason: inspect(reason))
         )
         |> push_event("close-modal", %{id: "add-kura-server-modal"})}
    end
  end

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  defp delete_cache_endpoint(socket, endpoint_id) do
    selected_account = socket.assigns.selected_account

    with endpoint when not is_nil(endpoint) <- Accounts.get_account_cache_endpoint(selected_account, endpoint_id),
         {:ok, _} <- Accounts.delete_account_cache_endpoint(endpoint) do
      {:ok, Accounts.list_account_cache_endpoints(selected_account)}
    else
      _ -> :error
    end
  end

  attr(:kura_servers, :list, required: true)
  attr(:available_kura_regions, :list, required: true)
  attr(:add_kura_server_form, Form, required: true)
  attr(:latest_kura_version, :map, default: nil)
  attr(:global_endpoint_url, :string, default: nil)

  def kura_servers_section(assigns) do
    ~H"""
    <.card_section data-part="kura-servers-card-section">
      <div data-part="header">
        <span data-part="title">
          {dgettext("dashboard_account", "Kura cache servers")}
        </span>
        <span data-part="subtitle">
          {dgettext(
            "dashboard_account",
            "Deploy regional Kura cache servers for this account. Each region can have at most one server."
          )}
        </span>
      </div>
      <div :if={Enum.any?(@available_kura_regions)} data-part="button-container">
        <.modal
          id="add-kura-server-modal"
          title={dgettext("dashboard_account", "Deploy Kura server")}
          header_size="large"
          on_dismiss="close-add-kura-server-modal"
        >
          <:trigger :let={attrs}>
            <.button
              id="add-kura-server-button"
              label={dgettext("dashboard_account", "Deploy Kura server")}
              variant="secondary"
              size="medium"
              disabled={Enum.empty?(@available_kura_regions)}
              type="button"
              {attrs}
            />
          </:trigger>
          <.form
            for={@add_kura_server_form}
            id="add-kura-server-form"
            phx-submit="create_kura_server"
          >
            <.line_divider />
            <div data-part="modal-content">
              <label data-part="select-label">
                {dgettext("dashboard_account", "Region")}
              </label>
              <%= case @available_kura_regions do %>
                <% [region] -> %>
                  <input type="hidden" name={@add_kura_server_form[:region].name} value={region.id} />
                  <div data-part="selected-region">
                    <.icon name="world" />
                    <span>{region.display_name}</span>
                  </div>
                <% _ -> %>
                  <.select
                    id="add-kura-server-region"
                    field={@add_kura_server_form[:region]}
                    label={dgettext("dashboard_account", "Region")}
                    disabled={Enum.empty?(@available_kura_regions)}
                  >
                    <:item
                      :for={region <- @available_kura_regions}
                      value={region.id}
                      label={region.display_name}
                      icon="world"
                    />
                  </.select>
              <% end %>
              <p data-part="hint">
                <%= case @latest_kura_version do %>
                  <% nil -> %>
                    {dgettext(
                      "dashboard_account",
                      "No Kura runtime image is configured right now. Try again after the next server deploy."
                    )}
                  <% version -> %>
                    {dgettext("dashboard_account", "New servers start on Kura")}
                    <strong>{version.version}</strong>
                    {dgettext("dashboard_account", "(current deploy).")}
                <% end %>
              </p>
            </div>
            <.line_divider />
          </.form>
          <:footer>
            <.modal_footer>
              <:action>
                <.button
                  type="button"
                  label={dgettext("dashboard_account", "Cancel")}
                  variant="secondary"
                  phx-click="close-add-kura-server-modal"
                />
              </:action>
              <:action>
                <%= case @available_kura_regions do %>
                  <% [region] -> %>
                    <button
                      type="button"
                      class="noora-button"
                      data-variant="primary"
                      data-size="large"
                      data-icon-only="false"
                      phx-click="create_kura_server"
                      phx-value-region={region.id}
                      disabled={is_nil(@latest_kura_version)}
                    >
                      <span>{dgettext("dashboard_account", "Deploy")}</span>
                    </button>
                  <% _ -> %>
                    <.button
                      type="submit"
                      form="add-kura-server-form"
                      label={dgettext("dashboard_account", "Deploy")}
                      variant="primary"
                      disabled={is_nil(@latest_kura_version) or Enum.empty?(@available_kura_regions)}
                    />
                <% end %>
              </:action>
            </.modal_footer>
          </:footer>
        </.modal>
      </div>
      <div data-part="content">
        <.alert
          :if={@global_endpoint_url && Enum.any?(@kura_servers)}
          status="information"
          type="secondary"
          size="small"
          title={
            dgettext(
              "dashboard_account",
              "Clients use the global Kura endpoint %{url}; Cloudflare DNS steers it to the nearest healthy region.",
              url: @global_endpoint_url
            )
          }
        />
        <.table
          :if={Enum.any?(@kura_servers) or Enum.any?(@available_kura_regions)}
          id="kura-servers-table"
          rows={kura_server_rows(@kura_servers, @available_kura_regions)}
        >
          <:col :let={row} label={dgettext("dashboard_account", "Region")}>
            <.text_cell label={kura_region_label(kura_row_region_id(row))} />
          </:col>
          <:col :let={row} label={dgettext("dashboard_account", "Status")}>
            <.badge_cell
              label={kura_row_status_label(row)}
              color={kura_row_status_color(row)}
              style="light-fill"
            />
          </:col>
          <:col :let={row} label={dgettext("dashboard_account", "Domain")}>
            <.text_cell label={kura_row_domain_label(row)} />
          </:col>
          <:col :let={row} label={dgettext("dashboard_account", "Version")}>
            <.text_cell label={kura_row_version_label(row)} />
          </:col>
          <:col :let={row} label="">
            <.button
              :if={kura_row_retry?(row)}
              type="button"
              label={dgettext("dashboard_account", "Retry")}
              variant="primary"
              size="small"
              phx-click="retry_kura_server"
              phx-value-id={row.server.id}
              disabled={is_nil(@latest_kura_version)}
            />
            <.button
              :if={kura_row_server?(row) and row.server.status not in [:destroying, :destroyed]}
              type="button"
              label={dgettext("dashboard_account", "Destroy")}
              variant="destructive"
              size="small"
              phx-click="destroy_kura_server"
              phx-value-id={row.server.id}
              data-confirm={
                dgettext(
                  "dashboard_account",
                  "Destroy the Kura server in %{region}? This removes the account's Kura cache endpoint for that region.",
                  region: row.server.region
                )
              }
            />
            <.button
              :if={kura_row_available_region?(row)}
              type="button"
              label={dgettext("dashboard_account", "Deploy")}
              variant="primary"
              size="small"
              phx-click="create_kura_server"
              phx-value-region={row.region.id}
              disabled={is_nil(@latest_kura_version)}
            />
          </:col>
        </.table>
      </div>
    </.card_section>
    """
  end

  defp kura_server_rows(servers, available_regions) do
    Enum.map(servers, &%{id: "server-#{&1.id}", type: :server, region_id: &1.region, server: &1}) ++
      Enum.map(
        available_regions,
        &%{
          id: "available-region-#{&1.id}",
          type: :available_region,
          region_id: &1.id,
          region: &1
        }
      )
  end

  defp kura_row_region_id(row), do: row.region_id

  defp kura_row_server?(%{type: :server}), do: true
  defp kura_row_server?(_row), do: false

  defp kura_row_available_region?(%{type: :available_region}), do: true
  defp kura_row_available_region?(_row), do: false

  # Retry is offered only on first-time deploys that never reached
  # `:active` (current_image_tag is nil): no traffic depends on the row,
  # so atomically tombstoning it and starting fresh is safe. Drift
  # failures on a previously-active server skip this — retrying would
  # tear down the cache endpoint that's still serving the old image.
  defp kura_row_retry?(%{type: :server, server: %{status: :failed, current_image_tag: nil}}), do: true
  defp kura_row_retry?(_row), do: false

  defp kura_row_status_label(%{type: :server, server: server}), do: kura_display_status_label(server)
  defp kura_row_status_label(%{type: :available_region}), do: dgettext("dashboard_account", "Not deployed")

  defp kura_row_status_color(%{type: :server, server: server}), do: kura_display_status_color(server)
  defp kura_row_status_color(%{type: :available_region}), do: "neutral"

  defp kura_row_domain_label(%{type: :server, server: server}) do
    server.url || dgettext("dashboard_account", "Pending")
  end

  defp kura_row_domain_label(%{type: :available_region}), do: dgettext("dashboard_account", "Pending")

  defp kura_row_version_label(%{type: :server, server: server}) do
    kura_version_label(server.current_image_tag) || dgettext("dashboard_account", "Pending")
  end

  defp kura_row_version_label(%{type: :available_region}), do: dgettext("dashboard_account", "Pending")

  def kura_display_status_label(server) do
    if show_deploying?(server),
      do: dgettext("dashboard_account", "Deploying"),
      else: kura_server_status_label(server.status)
  end

  def kura_display_status_color(server) do
    if show_deploying?(server),
      do: "information",
      else: kura_server_status_color(server.status)
  end

  def kura_server_status_label(:provisioning), do: dgettext("dashboard_account", "Deploying")
  def kura_server_status_label(:active), do: dgettext("dashboard_account", "Active")
  def kura_server_status_label(:failed), do: dgettext("dashboard_account", "Failed")
  def kura_server_status_label(:destroying), do: dgettext("dashboard_account", "Destroying")
  def kura_server_status_label(:destroyed), do: dgettext("dashboard_account", "Destroyed")

  def kura_server_status_color(:provisioning), do: "information"
  def kura_server_status_color(:active), do: "success"
  def kura_server_status_color(:failed), do: "destructive"
  def kura_server_status_color(:destroying), do: "warning"
  def kura_server_status_color(:destroyed), do: "neutral"

  defp show_deploying?(%{status: :provisioning}), do: true
  defp show_deploying?(_), do: false

  defp kura_region_label(region_id) do
    case Regions.get(region_id) do
      nil -> region_id
      region -> region.display_name
    end
  end

  defp kura_version_label(image_tag), do: Kura.version_label(image_tag)

  attr(:preferred_locale_form, :any, required: true)

  def preferred_locale_section(assigns) do
    languages = [%{code: "browser", label: dgettext("dashboard_account", "Browser default")} | SharedLocale.languages()]
    assigns = assign(assigns, :languages, languages)

    ~H"""
    <.card_section data-part="dashboard-language-card-section">
      <div data-part="header">
        <span data-part="title">
          {dgettext("dashboard_account", "Dashboard language")}
        </span>
        <span data-part="subtitle">
          {dgettext("dashboard_account", "Choose your preferred dashboard language.")}
        </span>
      </div>
      <div data-part="content">
        <label data-part="select-label">
          {dgettext("dashboard_account", "Language")}
        </label>
        <.select
          id="dashboard-language-selection"
          field={@preferred_locale_form[:preferred_locale]}
          label={dgettext("dashboard_account", "Language")}
          on_value_change="select_preferred_locale"
        >
          <:item
            :for={lang <- @languages}
            value={lang.code}
            label={
              if Map.has_key?(lang, :native), do: "#{lang.native} (#{lang.label})", else: lang.label
            }
            icon="language"
          />
        </.select>
      </div>
    </.card_section>
    """
  end

  attr(:region_form, Form, required: true)
  attr(:selected_account, Account, required: true)

  def region_selection_section(assigns) do
    ~H"""
    <.card_section data-part="region-card-section">
      <div data-part="header">
        <span data-part="title">
          {dgettext("dashboard_account", "Storage region")}
        </span>
        <span data-part="subtitle">
          {dgettext(
            "dashboard_account",
            "Choose where your artifacts, like module cache binaries, are stored for legal compliance."
          )}
        </span>
      </div>
      <div data-part="content">
        <label data-part="select-label">
          {dgettext("dashboard_account", "Select region")}
        </label>
        <.select
          id="region-selection"
          field={@region_form[:region]}
          label={dgettext("dashboard_account", "Region")}
          on_value_change="select_region"
        >
          <:item value="all" label={dgettext("dashboard_account", "All regions")} icon="world" />
          <:item value="europe" label={dgettext("dashboard_account", "Europe")} icon="world" />
          <:item value="usa" label={dgettext("dashboard_account", "United States")} icon="world" />
        </.select>
      </div>
    </.card_section>
    """
  end

  attr(:cache_endpoints, :list, required: true)
  attr(:add_cache_endpoint_form, Form, required: true)
  attr(:custom_cache_endpoints_enabled, :boolean, required: true)

  def cache_endpoints_section(assigns) do
    ~H"""
    <.card_section data-part="cache-endpoints-card-section">
      <div data-part="header">
        <div data-part="toggle-row">
          <.toggle
            id={"custom-cache-endpoints-toggle-#{@custom_cache_endpoints_enabled}"}
            checked={@custom_cache_endpoints_enabled}
            data-on-checked-change="toggle_custom_cache_endpoints"
          />
          <span data-part="title">
            {dgettext("dashboard_account", "Cache endpoints")}
          </span>
        </div>
        <span data-part="subtitle">
          {dgettext(
            "dashboard_account",
            "Configure custom cache endpoints for self-hosted cache setups. When enabled, Tuist will read from and write to these endpoints instead of the default Tuist-hosted cache."
          )}
        </span>
      </div>
      <div data-part="button-container">
        <.form
          for={@add_cache_endpoint_form}
          id="add-cache-endpoint-form"
          phx-submit="create_cache_endpoint"
        >
          <.modal
            id="add-cache-endpoint-modal"
            title={dgettext("dashboard_account", "Add cache endpoint")}
            header_size="large"
            on_dismiss="close-add-cache-endpoint-modal"
          >
            <:trigger :let={attrs}>
              <.button
                id={"add-cache-endpoint-button-#{@custom_cache_endpoints_enabled}"}
                label={dgettext("dashboard_account", "Add endpoint")}
                variant="secondary"
                size="medium"
                disabled={!@custom_cache_endpoints_enabled}
                type="button"
                {attrs}
              />
            </:trigger>
            <.line_divider />
            <div data-part="modal-content">
              <.text_input
                field={@add_cache_endpoint_form[:url]}
                type="basic"
                label={dgettext("dashboard_account", "Endpoint URL")}
                placeholder="https://cache.example.com"
              />
            </div>
            <.line_divider />
            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    type="reset"
                    label={dgettext("dashboard_account", "Cancel")}
                    variant="secondary"
                    phx-click="close-add-cache-endpoint-modal"
                  />
                </:action>
                <:action>
                  <.button
                    type="submit"
                    label={dgettext("dashboard_account", "Add")}
                    variant="primary"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </.form>
      </div>
      <div :if={@custom_cache_endpoints_enabled || !Enum.empty?(@cache_endpoints)} data-part="content">
        <.alert
          :if={!@custom_cache_endpoints_enabled}
          status="information"
          type="secondary"
          size="small"
          title={
            dgettext(
              "dashboard_account",
              "Custom cache endpoints are disabled. Tuist will use the default Tuist-hosted cache."
            )
          }
        />
        <.alert
          :if={@custom_cache_endpoints_enabled and Enum.empty?(@cache_endpoints)}
          status="information"
          type="secondary"
          size="small"
          title={
            dgettext(
              "dashboard_account",
              "No custom cache endpoints configured. Tuist will use the default Tuist-hosted cache until endpoints are added."
            )
          }
        />
        <.table
          :if={@custom_cache_endpoints_enabled and not Enum.empty?(@cache_endpoints)}
          id="cache-endpoints-table"
          rows={@cache_endpoints}
        >
          <:col :let={endpoint} label={dgettext("dashboard_account", "URL")}>
            <.text_cell label={endpoint.url} />
          </:col>
          <:col :let={endpoint} label="">
            <%= if length(@cache_endpoints) == 1 do %>
              <.modal
                id={"delete-endpoint-#{endpoint.id}-modal"}
                title={dgettext("dashboard_account", "Delete last cache endpoint?")}
                header_size="large"
                on_dismiss={"close-delete-endpoint-modal-#{endpoint.id}"}
              >
                <:trigger :let={attrs}>
                  <.button
                    type="button"
                    label={dgettext("dashboard_account", "Delete")}
                    variant="destructive"
                    size="small"
                    {attrs}
                  />
                </:trigger>
                <.line_divider />
                <div data-part="content">
                  <.alert
                    status="warning"
                    type="secondary"
                    size="small"
                    title={
                      dgettext(
                        "dashboard_account",
                        "Removing the last custom cache endpoint will switch your organization back to Tuist-hosted caching. This affects all builds across your organization."
                      )
                    }
                  />
                </div>
                <.line_divider />
                <:footer>
                  <.modal_footer>
                    <:action>
                      <.button
                        type="button"
                        label={dgettext("dashboard_account", "Cancel")}
                        variant="secondary"
                        phx-click={"close-delete-endpoint-modal-#{endpoint.id}"}
                      />
                    </:action>
                    <:action>
                      <.button
                        type="button"
                        label={dgettext("dashboard_account", "Delete")}
                        variant="destructive"
                        phx-click="confirm_delete_last_cache_endpoint"
                        phx-value-id={endpoint.id}
                      />
                    </:action>
                  </.modal_footer>
                </:footer>
              </.modal>
            <% else %>
              <.button
                type="button"
                label={dgettext("dashboard_account", "Delete")}
                variant="destructive"
                size="small"
                phx-click="delete_cache_endpoint"
                phx-value-id={endpoint.id}
              />
            <% end %>
          </:col>
        </.table>
      </div>
    </.card_section>
    """
  end
end
