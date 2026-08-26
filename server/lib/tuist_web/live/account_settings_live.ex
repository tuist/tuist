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
  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.Kura.Regions
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
    |> assign(:managed_kura_visible?, false)
    |> assign(:kura_serving_state, :absent)
  end

  defp load_kura_state(socket, _opts \\ []) do
    account = socket.assigns.selected_account

    # Customer-facing list only. Private runner-cache nodes are
    # control-plane-managed (provisioned/torn down by the identity rule), so
    # surfacing them here would report a cache the account cannot use.
    servers =
      account.id
      |> Kura.list_servers_for_account()
      |> Enum.reject(&Regions.private?(Regions.get(&1.region)))

    socket
    |> assign(:kura_servers, servers)
    # A deployment serving no public region runs nobody's cache, so there is
    # no managed cache to report the state of.
    |> assign(:managed_kura_visible?, servers != [] or Enum.any?(Regions.available(), &(not Regions.private?(&1))))
    |> assign(:kura_serving_state, kura_serving_state(servers))
  end

  # What the account is told, which is whether its cache is working — not where
  # it runs or how many there are. Naming a region here would invite a request
  # to change it, and placement is not a request the account can make.
  defp kura_serving_state(servers) do
    cond do
      Enum.any?(servers, &(&1.status == :active)) -> :active
      Enum.any?(servers, &(&1.status in [:provisioning, :replicating, :failed])) -> :preparing
      true -> :absent
    end
  end

  defp kura_enabled?(account) do
    FeatureFlags.kura_enabled?(account)
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

  attr(:kura_serving_state, :atom, required: true)

  def kura_servers_section(assigns) do
    ~H"""
    <.card_section data-part="kura-serving-card-section">
      <div data-part="header">
        <span data-part="title">
          {dgettext("dashboard_account", "Managed cache")}
        </span>
        <span data-part="subtitle">
          {dgettext(
            "dashboard_account",
            "Tuist runs your cache for you and keeps it close to where your builds run, following them if they move."
          )}
        </span>
      </div>
      <div data-part="content">
        <%= case @kura_serving_state do %>
          <% :active -> %>
            <.badge
              label={dgettext("dashboard_account", "Active")}
              color="success"
              style="light-fill"
            />
            <span data-part="kura-serving-description">
              {dgettext("dashboard_account", "Your cache is serving builds. Nothing to configure.")}
            </span>
          <% :preparing -> %>
            <.badge
              label={dgettext("dashboard_account", "Setting up")}
              color="attention"
              style="light-fill"
            />
            <span data-part="kura-serving-description">
              {dgettext(
                "dashboard_account",
                "Your cache is being set up. Builds keep working while it warms up."
              )}
            </span>
          <% :absent -> %>
            <.badge
              label={dgettext("dashboard_account", "Not running yet")}
              color="neutral"
              style="light-fill"
            />
            <span data-part="kura-serving-description">
              {dgettext("dashboard_account", "Your cache starts the first time a build uses it.")}
            </span>
        <% end %>
      </div>
    </.card_section>
    """
  end

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
  def kura_server_status_label(:replicating), do: dgettext("dashboard_account", "Replicating")
  def kura_server_status_label(:active), do: dgettext("dashboard_account", "Active")
  def kura_server_status_label(:failed), do: dgettext("dashboard_account", "Failed")
  def kura_server_status_label(:destroying), do: dgettext("dashboard_account", "Destroying")
  def kura_server_status_label(:destroyed), do: dgettext("dashboard_account", "Destroyed")
  def kura_server_status_label(:drain_pending), do: dgettext("dashboard_account", "Draining")
  # Distinct from both "Not deployed" (never had a cache here) and
  # "Destroyed" (an operator tore it down): the cache was reclaimed after a
  # full inactivity window, and the next build brings it back on its own.
  def kura_server_status_label(:archived), do: dgettext("dashboard_account", "Archived (inactive)")

  def kura_server_status_color(:provisioning), do: "information"
  def kura_server_status_color(:replicating), do: "information"
  def kura_server_status_color(:active), do: "success"
  def kura_server_status_color(:failed), do: "destructive"
  def kura_server_status_color(:destroying), do: "warning"
  def kura_server_status_color(:destroyed), do: "neutral"
  def kura_server_status_color(:drain_pending), do: "warning"
  def kura_server_status_color(:archived), do: "neutral"

  defp show_deploying?(%{status: :provisioning}), do: true
  defp show_deploying?(_), do: false

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
