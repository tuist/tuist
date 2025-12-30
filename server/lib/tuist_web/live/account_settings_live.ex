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

    socket =
      socket
      |> assign(selected_tab: "settings")
      |> assign(rename_account_form: rename_account_form)
      |> assign(delete_organization_form: delete_organization_form)
      |> assign(delete_user_form: delete_user_form)
      |> assign(region_form: region_form)
      |> assign(add_cache_endpoint_form: add_cache_endpoint_form)
      |> assign(cache_endpoints: cache_endpoints)
      |> assign(:head_title, "#{dgettext("dashboard_account", "Settings")} · #{selected_account.name} · Tuist")

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

  defp delete_cache_endpoint(socket, endpoint_id) do
    selected_account = socket.assigns.selected_account

    with endpoint when not is_nil(endpoint) <- Accounts.get_account_cache_endpoint(selected_account, endpoint_id),
         {:ok, _} <- Accounts.delete_account_cache_endpoint(endpoint) do
      {:ok, Accounts.list_account_cache_endpoints(selected_account)}
    else
      _ -> :error
    end
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

  def cache_endpoints_section(assigns) do
    ~H"""
    <.card_section data-part="cache-endpoints-card-section">
      <div data-part="header">
        <span data-part="title">
          {dgettext("dashboard_account", "Custom cache endpoints")}
        </span>
        <span data-part="subtitle">
          {dgettext(
            "dashboard_account",
            "Configure custom cache endpoints for self-hosted cache scenarios. When configured, these endpoints will be used instead of the default Tuist-hosted endpoints."
          )}
        </span>
      </div>
      <div data-part="content">
        <%= if Enum.empty?(@cache_endpoints) do %>
          <.alert
            status="information"
            type="secondary"
            size="small"
            title={
              dgettext(
                "dashboard_account",
                "No custom cache endpoints configured. Default Tuist-hosted endpoints will be used."
              )
            }
          />
        <% else %>
          <.table id="cache-endpoints-table" rows={@cache_endpoints}>
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
        <% end %>
        <.form
          data-part="form"
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
                label={dgettext("dashboard_account", "Add endpoint")}
                variant="secondary"
                size="medium"
                {attrs}
              />
            </:trigger>
            <.line_divider />
            <div data-part="content">
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
    </.card_section>
    """
  end
end
