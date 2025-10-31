defmodule TuistWeb.AccountSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Phoenix.HTML.Form
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Authorization

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            gettext("You are not authorized to perform this action.")
    end

    rename_account_form = to_form(Account.update_changeset(selected_account, %{}))
    delete_organization_form = to_form(%{"name" => ""})
    delete_user_form = to_form(%{"name" => ""})
    region_form = to_form(Account.update_changeset(selected_account, %{}))

    socket =
      socket
      |> assign(selected_tab: "settings")
      |> assign(rename_account_form: rename_account_form)
      |> assign(delete_organization_form: delete_organization_form)
      |> assign(delete_user_form: delete_user_form)
      |> assign(region_form: region_form)
      |> assign(:head_title, "#{gettext("Settings")} · #{selected_account.name} · Tuist")

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

  def handle_event("select_region", %{"value" => [value]}, socket) do
    region = String.to_existing_atom(value)
    changeset = Account.update_changeset(socket.assigns.selected_account, %{region: region})
    region_form = to_form(changeset)
    socket = assign(socket, region_form: region_form)

    {:noreply, socket}
  end

  def handle_event(
        "update_region",
        %{"account" => account_params},
        %{assigns: %{selected_account: selected_account}} = socket
      ) do
    case Accounts.update_account(selected_account, account_params) do
      {:ok, account} ->
        region_form = to_form(Account.update_changeset(account, %{}))

        socket =
          socket
          |> assign(selected_account: account)
          |> assign(region_form: region_form)
          |> put_flash(:info, gettext("Binary cache region updated successfully"))

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, region_form: to_form(changeset))}

      _error ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update region"))}
    end
  end

  # Fallback handler for when form submits empty data
  def handle_event(
        "update_region",
        _params,
        %{assigns: %{selected_account: selected_account, region_form: region_form}} = socket
      ) do
    # Get the region value from the current form state
    region = Form.input_value(region_form, :region) || selected_account.region

    case Accounts.update_account(selected_account, %{region: region}) do
      {:ok, account} ->
        region_form = to_form(Account.update_changeset(account, %{}))

        socket =
          socket
          |> assign(selected_account: account)
          |> assign(region_form: region_form)
          |> put_flash(:info, gettext("Binary cache region updated successfully"))

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, region_form: to_form(changeset))}

      _error ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update region"))}
    end
  end

  attr(:region_form, Form, required: true)
  attr(:selected_account, Account, required: true)

  def region_selection_section(assigns) do
    ~H"""
    <.card_section data-part="region-card-section">
      <div data-part="header">
        <span data-part="title">
          {gettext("Storage region")}
        </span>
        <span data-part="subtitle">
          {gettext(
            "Choose where your artifacts, like module cache binaries, are stored for legal compliance."
          )}
        </span>
      </div>
      <div data-part="content">
        <.form
          data-part="form"
          for={@region_form}
          id="update-region"
          phx-submit="update_region"
        >
          <.select
            id="region-selection"
            field={@region_form[:region]}
            label={gettext("Region")}
            on_value_change="select_region"
          >
            <:item value="all" label="All regions" />
            <:item value="europe" label="Europe" />
            <:item value="usa" label="United States" />
          </.select>
          <.button
            label={gettext("Update region")}
            variant="primary"
            size="medium"
            type="submit"
          />
        </.form>
      </div>
    </.card_section>
    """
  end
end
