defmodule TuistWeb.CacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Phoenix.HTML.Form
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Registrations
  alias Tuist.Kura.SelfHostedClients
  alias Tuist.Kura.Server

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    cache_enabled = cache_enabled?(selected_account)
    if connected?(socket) and cache_enabled, do: Kura.subscribe_to_account(selected_account.id)

    socket =
      socket
      |> assign(:cache_enabled, cache_enabled)
      |> assign(:head_title, "#{dgettext("dashboard_account", "Cache")} · #{selected_account.name} · Tuist")
      |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))
      |> assign(:new_self_hosted_client_secret, nil)
      |> load_servers_state()
      |> load_self_hosted_state()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open-add-cache-server", _params, socket) do
    {:noreply, push_event(socket, "open-modal", %{id: "add-cache-server-modal"})}
  end

  def handle_event("close-add-cache-server-modal", _params, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "add-cache-server-modal"})
      |> assign(:add_cache_server_form, default_server_form(socket.assigns.available_regions))

    {:noreply, socket}
  end

  def handle_event("create_cache_server", params, %{assigns: %{cache_enabled: true}} = socket) do
    case {region_from_params(params, socket.assigns.available_regions), socket.assigns.latest_version} do
      {nil, _} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("dashboard_account", "Select a region before deploying."))
         |> push_event("close-modal", %{id: "add-cache-server-modal"})}

      {_region, nil} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext(
             "dashboard_account",
             "No runtime image is configured right now. Try again after the next server deploy."
           )
         )
         |> push_event("close-modal", %{id: "add-cache-server-modal"})}

      {region, version} ->
        attrs = %{
          account_id: socket.assigns.selected_account.id,
          region: region,
          image_tag: version_image_tag(version)
        }

        create_cache_server(socket, attrs)
    end
  end

  def handle_event("create_cache_server", _params, socket), do: {:noreply, socket}

  def handle_event("destroy_cache_server", %{"id" => id}, %{assigns: %{cache_enabled: true}} = socket) do
    case Kura.get_server(socket.assigns.selected_account.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_account", "Cache server not found."))}

      %Server{} = server ->
        {:ok, _} = Kura.destroy_server(server)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_account", "Destroying cache server..."))
         |> load_servers_state()}
    end
  end

  def handle_event("destroy_cache_server", _params, socket), do: {:noreply, socket}

  def handle_event("retry_cache_server", %{"id" => id}, %{assigns: %{cache_enabled: true}} = socket) do
    with %Server{} = server <- Kura.get_server(socket.assigns.selected_account.id, id),
         version when not is_nil(version) <- socket.assigns.latest_version,
         {:ok, _} <- Kura.retry_server(server, version_image_tag(version)) do
      {:noreply, load_servers_state(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("retry_cache_server", _params, socket), do: {:noreply, socket}

  def handle_event(
        "create_self_hosted_client",
        params,
        %{assigns: %{cache_enabled: true, selected_account: account}} = socket
      ) do
    case SelfHostedClients.create_self_hosted_client(account, %{name: get_in(params, ["self_hosted_client", "name"])}) do
      {:ok, {client, secret}} ->
        # Keep the modal open and swap its body to the one-time secret
        # disclosure (mirrors the webhook signing-secret flow).
        {:noreply,
         socket
         |> assign(:new_self_hosted_client_secret, %{
           client_id: client.client_id,
           secret: secret,
           name: client.name
         })
         |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))
         |> load_self_hosted_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :new_self_hosted_client_form, to_form(changeset))}
    end
  end

  def handle_event("create_self_hosted_client", _params, socket), do: {:noreply, socket}

  def handle_event("dismiss_self_hosted_client_secret", _params, socket) do
    {:noreply,
     socket
     |> reset_self_hosted_client_modal()
     |> push_event("close-modal", %{id: "add-self-hosted-client-modal"})}
  end

  def handle_event("self_hosted_client_modal_open_change", %{"open" => false}, socket) do
    {:noreply, reset_self_hosted_client_modal(socket)}
  end

  def handle_event("self_hosted_client_modal_open_change", _params, socket), do: {:noreply, socket}

  def handle_event("revoke_self_hosted_client", %{"id" => id}, socket) do
    socket = push_event(socket, "close-modal", %{id: "revoke-credential-modal-#{id}"})

    case Enum.find(socket.assigns.self_hosted_clients, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      client ->
        {:ok, _} = SelfHostedClients.revoke_self_hosted_client(client)
        {:noreply, load_self_hosted_state(socket)}
    end
  end

  def handle_event("close-revoke-credential-modal-" <> id, _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "revoke-credential-modal-#{id}"})}
  end

  def handle_event("close-add-self-hosted-client-modal", _params, socket) do
    {:noreply,
     socket
     |> push_event("close-modal", %{id: "add-self-hosted-client-modal"})
     |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))}
  end

  @impl true
  def handle_info({:kura_server, _event, _server}, %{assigns: %{cache_enabled: true}} = socket) do
    {:noreply, load_servers_state(socket)}
  end

  def handle_info({:kura_server, _event, _server}, socket), do: {:noreply, socket}

  defp load_servers_state(%{assigns: %{cache_enabled: false}} = socket) do
    socket
    |> assign(:servers, [])
    |> assign(:regions, [])
    |> assign(:available_regions, [])
    |> assign(:latest_version, nil)
    |> assign(:add_cache_server_form, default_server_form([]))
  end

  defp load_servers_state(socket, opts \\ []) do
    account = socket.assigns.selected_account

    # Customer-facing list only. Private runner-cache nodes are
    # control-plane-managed (provisioned/torn down by the identity rule) —
    # surfacing them here would expose an in-cluster URL and a Destroy button
    # that just fights the reconciler.
    servers =
      account.id
      |> Kura.list_servers_for_account()
      |> Enum.reject(&Regions.private?(Regions.get(&1.region)))

    regions = Regions.selectable()
    available_regions = available_regions(regions, servers)
    latest = Keyword.get_lazy(opts, :latest_version, fn -> List.first(Kura.latest_versions(1)) end)

    socket
    |> assign(:servers, servers)
    |> assign(:regions, regions)
    |> assign(:available_regions, available_regions)
    |> assign(:latest_version, latest)
    |> assign(:add_cache_server_form, default_server_form(available_regions))
  end

  defp reset_self_hosted_client_modal(socket) do
    socket
    |> assign(:new_self_hosted_client_secret, nil)
    |> assign(:new_self_hosted_client_form, to_form(%{"name" => ""}, as: :self_hosted_client))
  end

  defp load_self_hosted_state(%{assigns: %{cache_enabled: false}} = socket) do
    socket
    |> assign(:self_hosted_clients, [])
    |> assign(:registered_endpoints, [])
  end

  defp load_self_hosted_state(%{assigns: %{selected_account: account}} = socket) do
    socket
    |> assign(:self_hosted_clients, SelfHostedClients.list_self_hosted_clients(account))
    |> assign(:registered_endpoints, Registrations.list_endpoints(account))
  end

  defp cache_enabled?(account) do
    Environment.dev?() or FunWithFlags.enabled?(:kura, for: account)
  end

  defp available_regions(regions, servers) do
    occupied_regions = MapSet.new(servers, & &1.region)
    Enum.reject(regions, &MapSet.member?(occupied_regions, &1.id))
  end

  defp region_from_params(params, available_regions) do
    # Only honor a submitted region that is actually offered to this account
    # right now — params are client-controlled, and a crafted LiveView event
    # could otherwise name a private (runner-cache) or already-occupied region
    # that `Kura.create_server/1` accepts.
    available_ids = MapSet.new(available_regions, & &1.id)

    [
      get_in(params, ["server", "region"]),
      params["region"]
    ]
    |> Enum.find(&present?/1)
    |> case do
      nil -> single_available_region_id(available_regions)
      region -> if MapSet.member?(available_ids, region), do: region
    end
  end

  defp single_available_region_id([region]), do: region.id
  defp single_available_region_id(_regions), do: nil

  defp version_image_tag(%{image_tag: image_tag}), do: image_tag
  defp version_image_tag(%{version: "kura@" <> image_tag}), do: image_tag
  defp version_image_tag(%{version: image_tag}), do: image_tag

  defp present?(value), do: is_binary(value) and value != ""

  defp default_server_form([]), do: to_form(%{"region" => nil}, as: :server)

  defp default_server_form([region | _]) do
    to_form(%{"region" => region.id}, as: :server)
  end

  defp create_cache_server(socket, attrs) do
    case Kura.create_server(attrs) do
      {:ok, server} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("dashboard_account", "Deploying cache server in %{region}...", region: server.region)
         )
         |> push_event("close-modal", %{id: "add-cache-server-modal"})
         |> load_servers_state(latest_version: socket.assigns.latest_version)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_account", "Failed to deploy cache server: %{reason}", reason: format_errors(changeset))
         )
         |> push_event("close-modal", %{id: "add-cache-server-modal"})}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_account", "Failed to deploy cache server: %{reason}", reason: inspect(reason))
         )
         |> push_event("close-modal", %{id: "add-cache-server-modal"})}
    end
  end

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  defp server_rows(servers, available_regions) do
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

  defp row_region_id(row), do: row.region_id

  defp row_server?(%{type: :server}), do: true
  defp row_server?(_row), do: false

  defp row_available_region?(%{type: :available_region}), do: true
  defp row_available_region?(_row), do: false

  # Retry is offered only on first-time deploys that never reached `:active`
  # (current_image_tag is nil): no traffic depends on the row, so atomically
  # tombstoning it and starting fresh is safe. Drift failures on a
  # previously-active server skip this — retrying would tear down the cache
  # endpoint that's still serving the old image.
  defp row_retry?(%{type: :server, server: %{status: :failed, current_image_tag: nil}}), do: true
  defp row_retry?(_row), do: false

  defp row_status_label(%{type: :server, server: server}), do: display_status_label(server)
  defp row_status_label(%{type: :available_region}), do: dgettext("dashboard_account", "Not deployed")

  defp row_status_color(%{type: :server, server: server}), do: display_status_color(server)
  defp row_status_color(%{type: :available_region}), do: "neutral"

  defp row_domain_label(%{type: :server, server: server}) do
    server.url || dgettext("dashboard_account", "Pending")
  end

  defp row_domain_label(%{type: :available_region}), do: dgettext("dashboard_account", "Pending")

  # Prefer the image the cluster actually reports running
  # (`observed_image_tag`) over the last activated image, so a rollout in
  # flight or drift is visible; fall back while nothing has been observed yet.
  defp row_version_label(%{type: :server, server: server}) do
    version_label(server.observed_image_tag || server.current_image_tag) ||
      dgettext("dashboard_account", "Pending")
  end

  defp row_version_label(%{type: :available_region}), do: dgettext("dashboard_account", "Pending")

  defp display_status_label(server) do
    if show_deploying?(server),
      do: dgettext("dashboard_account", "Deploying"),
      else: server_status_label(server.status)
  end

  defp display_status_color(server) do
    if show_deploying?(server),
      do: "information",
      else: server_status_color(server.status)
  end

  defp server_status_label(:provisioning), do: dgettext("dashboard_account", "Deploying")
  defp server_status_label(:active), do: dgettext("dashboard_account", "Active")
  defp server_status_label(:failed), do: dgettext("dashboard_account", "Failed")
  defp server_status_label(:destroying), do: dgettext("dashboard_account", "Destroying")
  defp server_status_label(:destroyed), do: dgettext("dashboard_account", "Destroyed")

  defp server_status_color(:provisioning), do: "information"
  defp server_status_color(:active), do: "success"
  defp server_status_color(:failed), do: "destructive"
  defp server_status_color(:destroying), do: "warning"
  defp server_status_color(:destroyed), do: "neutral"

  defp show_deploying?(%{status: :provisioning}), do: true
  defp show_deploying?(_), do: false

  defp region_label(region_id) do
    case Regions.get(region_id) do
      nil -> region_id
      region -> region.display_name
    end
  end

  defp version_label(image_tag), do: Kura.version_label(image_tag)

  attr(:servers, :list, required: true)
  attr(:available_regions, :list, required: true)
  attr(:add_cache_server_form, Form, required: true)
  attr(:latest_version, :map, default: nil)

  def cache_servers_section(assigns) do
    ~H"""
    <.card_section data-part="servers-card">
      <div data-part="header">
        <div data-part="title-group">
          <span data-part="title">{dgettext("dashboard_account", "Cache servers")}</span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_account",
              "Deploy regional cache servers managed by Tuist. Each region can have at most one server."
            )}
          </span>
        </div>
        <div :if={Enum.any?(@available_regions)} data-part="actions">
          <.modal
            id="add-cache-server-modal"
            title={dgettext("dashboard_account", "Deploy server")}
            header_size="large"
            on_dismiss="close-add-cache-server-modal"
          >
            <:trigger :let={attrs}>
              <.button
                id="add-cache-server-button"
                label={dgettext("dashboard_account", "Deploy server")}
                variant="secondary"
                size="medium"
                type="button"
                {attrs}
              />
            </:trigger>
            <.form
              for={@add_cache_server_form}
              id="add-cache-server-form"
              phx-submit="create_cache_server"
            >
              <.line_divider />
              <div data-part="modal-content">
                <label data-part="select-label">{dgettext("dashboard_account", "Region")}</label>
                <%= case @available_regions do %>
                  <% [region] -> %>
                    <input
                      type="hidden"
                      name={@add_cache_server_form[:region].name}
                      value={region.id}
                    />
                    <div data-part="selected-region">
                      <.icon name="world" />
                      <span>{region.display_name}</span>
                    </div>
                  <% _ -> %>
                    <.select
                      id="add-cache-server-region"
                      field={@add_cache_server_form[:region]}
                      label={dgettext("dashboard_account", "Region")}
                      disabled={Enum.empty?(@available_regions)}
                    >
                      <:item
                        :for={region <- @available_regions}
                        value={region.id}
                        label={region.display_name}
                        icon="world"
                      />
                    </.select>
                <% end %>
                <p data-part="hint">
                  <%= case @latest_version do %>
                    <% nil -> %>
                      {dgettext(
                        "dashboard_account",
                        "No runtime image is configured right now. Try again after the next server deploy."
                      )}
                    <% version -> %>
                      {dgettext("dashboard_account", "New servers start on")}
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
                    phx-click="close-add-cache-server-modal"
                  />
                </:action>
                <:action>
                  <%= case @available_regions do %>
                    <% [region] -> %>
                      <button
                        type="button"
                        class="noora-button"
                        data-variant="primary"
                        data-size="large"
                        data-icon-only="false"
                        phx-click="create_cache_server"
                        phx-value-region={region.id}
                        disabled={is_nil(@latest_version)}
                      >
                        <span>{dgettext("dashboard_account", "Deploy")}</span>
                      </button>
                    <% _ -> %>
                      <.button
                        type="submit"
                        form="add-cache-server-form"
                        label={dgettext("dashboard_account", "Deploy")}
                        variant="primary"
                        disabled={is_nil(@latest_version) or Enum.empty?(@available_regions)}
                      />
                  <% end %>
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>
      <.table id="cache-servers-table" rows={server_rows(@servers, @available_regions)}>
        <:col :let={row} label={dgettext("dashboard_account", "Region")}>
          <.text_cell label={region_label(row_region_id(row))} />
        </:col>
        <:col :let={row} label={dgettext("dashboard_account", "Status")}>
          <.badge_cell label={row_status_label(row)} color={row_status_color(row)} style="light-fill" />
        </:col>
        <:col :let={row} label={dgettext("dashboard_account", "Domain")}>
          <.text_cell label={row_domain_label(row)} />
        </:col>
        <:col :let={row} label={dgettext("dashboard_account", "Version")}>
          <.text_cell label={row_version_label(row)} />
        </:col>
        <:col :let={row} label="">
          <.button
            :if={row_retry?(row)}
            type="button"
            label={dgettext("dashboard_account", "Retry")}
            variant="primary"
            size="small"
            phx-click="retry_cache_server"
            phx-value-id={row.server.id}
            disabled={is_nil(@latest_version)}
          />
          <.button
            :if={row_server?(row) and row.server.status not in [:destroying, :destroyed]}
            type="button"
            label={dgettext("dashboard_account", "Destroy")}
            variant="destructive"
            size="small"
            phx-click="destroy_cache_server"
            phx-value-id={row.server.id}
            data-confirm={
              dgettext(
                "dashboard_account",
                "Destroy the cache server in %{region}? This removes the account's cache endpoint for that region.",
                region: row.server.region
              )
            }
          />
          <.button
            :if={row_available_region?(row)}
            type="button"
            label={dgettext("dashboard_account", "Deploy")}
            variant="primary"
            size="small"
            phx-click="create_cache_server"
            phx-value-region={row.region.id}
            disabled={is_nil(@latest_version)}
          />
        </:col>
        <:empty_state>
          <.table_empty_state
            title={dgettext("dashboard_account", "No cache servers available")}
            subtitle={dgettext("dashboard_account", "No regions are available for this account yet.")}
          />
        </:empty_state>
      </.table>
    </.card_section>
    """
  end

  attr(:self_hosted_clients, :list, required: true)
  attr(:new_self_hosted_client_form, Form, required: true)
  attr(:new_self_hosted_client_secret, :map, default: nil)
  attr(:registered_endpoints, :list, required: true)

  def self_hosted_section(assigns) do
    ~H"""
    <.card_section data-part="self-hosted-card">
      <div data-part="header">
        <div data-part="title-group">
          <span data-part="title">
            {dgettext("dashboard_account", "Self-hosted cache servers")}
          </span>
          <span data-part="subtitle">
            {dgettext(
              "dashboard_account",
              "Run your own cache nodes. Generate a credential they authenticate with, and they register themselves so the CLI can reach them directly."
            )}
          </span>
        </div>
      </div>

      <div data-part="subsection">
        <div data-part="subsection-header">
          <div data-part="title-group">
            <span data-part="title">{dgettext("dashboard_account", "Credentials")}</span>
            <span data-part="subtitle">
              {dgettext(
                "dashboard_account",
                "Tenant-scoped credentials your nodes present to Tuist. A credential only authorizes this account's traffic."
              )}
            </span>
          </div>
          <div data-part="actions">
            <.form
              for={@new_self_hosted_client_form}
              id="add-self-hosted-client-form"
              phx-submit="create_self_hosted_client"
            >
              <%!-- Noora's modal shell is `phx-update="ignore"`, so we keep the --%>
              <%!-- title neutral and swap the body between the form and the --%>
              <%!-- one-time secret disclosure (mirrors the webhook flow). --%>
              <.modal
                id="add-self-hosted-client-modal"
                title={dgettext("dashboard_account", "Node credential")}
                on_dismiss="dismiss_self_hosted_client_secret"
                on_open_change="self_hosted_client_modal_open_change"
              >
                <:trigger :let={attrs}>
                  <.button
                    id="add-self-hosted-client-button"
                    label={dgettext("dashboard_account", "Generate credential")}
                    variant="secondary"
                    size="medium"
                    type="button"
                    {attrs}
                  />
                </:trigger>

                <div data-part="modal-content-wrapper">
                  <.line_divider />

                  <%= if @new_self_hosted_client_secret do %>
                    <div data-part="modal-body">
                      <div data-part="modal-message">
                        <span data-part="title">
                          {dgettext("dashboard_account", "Client credentials")}
                        </span>
                        <span data-part="subtitle">
                          {dgettext(
                            "dashboard_account",
                            "Copy the secret now. It will not be shown again after you close this dialog."
                          )}
                        </span>
                      </div>
                      <div data-part="credential-field">
                        <span data-part="label">
                          {dgettext("dashboard_account", "Client ID")}
                        </span>
                        <div data-part="read-only-value">
                          <code>{@new_self_hosted_client_secret.client_id}</code>
                          <.button
                            id="copy-self-hosted-client-id-button"
                            variant="secondary"
                            size="small"
                            icon_only
                            type="button"
                            phx-hook="Clipboard"
                            data-clipboard-value={@new_self_hosted_client_secret.client_id}
                            aria-label={dgettext("dashboard_account", "Copy client ID")}
                          >
                            <.copy />
                          </.button>
                        </div>
                      </div>
                      <div data-part="credential-field">
                        <span data-part="label">
                          {dgettext("dashboard_account", "Client secret")}
                        </span>
                        <div data-part="read-only-value">
                          <code id="new-self-hosted-client-secret">
                            {@new_self_hosted_client_secret.secret}
                          </code>
                          <.button
                            id="copy-self-hosted-client-secret-button"
                            variant="secondary"
                            size="small"
                            icon_only
                            type="button"
                            phx-hook="Clipboard"
                            data-clipboard-value={@new_self_hosted_client_secret.secret}
                            aria-label={dgettext("dashboard_account", "Copy client secret")}
                          >
                            <.copy />
                          </.button>
                        </div>
                      </div>
                    </div>
                  <% else %>
                    <div data-part="modal-body">
                      <.text_input
                        field={@new_self_hosted_client_form[:name]}
                        type="basic"
                        label={dgettext("dashboard_account", "Name")}
                        placeholder={dgettext("dashboard_account", "Production mesh")}
                      />
                    </div>
                  <% end %>

                  <.line_divider />
                </div>

                <:footer>
                  <.modal_footer>
                    <:action :if={@new_self_hosted_client_secret}>
                      <.button
                        type="button"
                        label={dgettext("dashboard_account", "Done")}
                        variant="primary"
                        phx-click="dismiss_self_hosted_client_secret"
                      />
                    </:action>
                    <:action :if={is_nil(@new_self_hosted_client_secret)}>
                      <.button
                        type="button"
                        label={dgettext("dashboard_account", "Cancel")}
                        variant="secondary"
                        phx-click="dismiss_self_hosted_client_secret"
                      />
                    </:action>
                    <:action :if={is_nil(@new_self_hosted_client_secret)}>
                      <.button
                        type="submit"
                        label={dgettext("dashboard_account", "Generate")}
                        variant="primary"
                      />
                    </:action>
                  </.modal_footer>
                </:footer>
              </.modal>
            </.form>
          </div>
        </div>
        <.table id="self-hosted-clients-table" rows={@self_hosted_clients}>
          <:col :let={client} label={dgettext("dashboard_account", "Name")}>
            <.text_cell label={client.name} />
          </:col>
          <:col :let={client} label={dgettext("dashboard_account", "Client ID")}>
            <.text_cell label={client.client_id} />
          </:col>
          <:col :let={client} label={dgettext("dashboard_account", "Secret")}>
            <.text_cell label={masked_secret(client.secret_last_four)} />
          </:col>
          <:col :let={client} label="">
            <.button_cell>
              <:button>
                <.modal
                  id={"revoke-credential-modal-#{client.id}"}
                  title={dgettext("dashboard_account", "Revoke credential")}
                  header_type="icon"
                  header_size="small"
                  on_dismiss={"close-revoke-credential-modal-#{client.id}"}
                >
                  <:trigger :let={attrs}>
                    <.button
                      type="button"
                      variant="secondary"
                      size="small"
                      icon_only
                      aria-label={dgettext("dashboard_account", "Revoke credential")}
                      {attrs}
                    >
                      <.trash />
                    </.button>
                  </:trigger>
                  <:header_icon>
                    <.trash />
                  </:header_icon>
                  <.line_divider />
                  <p data-part="revoke-credential-message">
                    {dgettext(
                      "dashboard_account",
                      "Revoke %{name}? Self-hosted nodes using it will stop authenticating.",
                      name: client.name
                    )}
                  </p>
                  <:footer>
                    <.modal_footer>
                      <:action>
                        <.button
                          label={dgettext("dashboard_account", "Cancel")}
                          variant="secondary"
                          type="button"
                          phx-click={"close-revoke-credential-modal-#{client.id}"}
                        />
                      </:action>
                      <:action>
                        <.button
                          label={dgettext("dashboard_account", "Revoke")}
                          variant="destructive"
                          type="button"
                          phx-click="revoke_self_hosted_client"
                          phx-value-id={client.id}
                        />
                      </:action>
                    </.modal_footer>
                  </:footer>
                </.modal>
              </:button>
            </.button_cell>
          </:col>
          <:empty_state>
            <.table_empty_state
              title={dgettext("dashboard_account", "No credentials yet")}
              subtitle={
                dgettext("dashboard_account", "Generate one to authorize your self-hosted nodes.")
              }
            />
          </:empty_state>
        </.table>
      </div>

      <.line_divider />

      <div data-part="subsection">
        <div data-part="subsection-header">
          <div data-part="title-group">
            <span data-part="title">{dgettext("dashboard_account", "Registered nodes")}</span>
            <span data-part="subtitle">
              {dgettext(
                "dashboard_account",
                "Self-hosted nodes reporting in via registration heartbeats. The CLI routes cache traffic to each node's endpoint, and a node drops off this list when it stops heartbeating."
              )}
            </span>
          </div>
        </div>
        <.table id="registered-nodes-table" rows={@registered_endpoints}>
          <:col :let={node} label={dgettext("dashboard_account", "Node")}>
            <.text_cell label={node.node_id} />
          </:col>
          <:col :let={node} label={dgettext("dashboard_account", "Endpoint")}>
            <.text_cell label={node.advertised_http_url} />
          </:col>
          <:col :let={node} label={dgettext("dashboard_account", "Region")}>
            <.text_cell label={node.region || "—"} />
          </:col>
          <:col :let={node} label={dgettext("dashboard_account", "Version")}>
            <.text_cell label={node.version || "—"} />
          </:col>
          <:col :let={node} label={dgettext("dashboard_account", "Status")}>
            <.badge_cell
              label={registered_status_label(node)}
              color={registered_status_color(node)}
              style="light-fill"
            />
          </:col>
          <:col :let={node} label={dgettext("dashboard_account", "Last heartbeat")}>
            <.text_cell label={Tuist.Utilities.DateFormatter.from_now(node.last_heartbeat_at)} />
          </:col>
          <:empty_state>
            <.table_empty_state
              title={dgettext("dashboard_account", "No registered nodes")}
              subtitle={
                dgettext(
                  "dashboard_account",
                  "Self-hosted nodes appear here once they start sending registration heartbeats."
                )
              }
            />
          </:empty_state>
        </.table>
      </div>
    </.card_section>
    """
  end

  defp registered_status_label(%{ready: true}), do: dgettext("dashboard_account", "Ready")
  defp registered_status_label(_), do: dgettext("dashboard_account", "Not ready")

  defp registered_status_color(%{ready: true}), do: "success"
  defp registered_status_color(_), do: "warning"

  # Suffix-only preview so a customer can match a credential against a secret
  # stored elsewhere; credentials issued before the hint existed show fully masked.
  defp masked_secret(tail) when is_binary(tail) and tail != "", do: String.duplicate("•", 12) <> tail
  defp masked_secret(_), do: String.duplicate("•", 16)
end
