defmodule TuistWeb.AccountSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Authorization

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_settings_update, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            gettext("You are not authorized to perform this action.")
    end

    rename_account_form = to_form(Account.update_changeset(selected_account, %{}))
    delete_organization_form = to_form(%{"name" => ""})
    delete_user_form = to_form(%{"name" => ""})

    socket =
      socket
      |> assign(selected_tab: "settings")
      |> assign(rename_account_form: rename_account_form)
      |> assign(delete_organization_form: delete_organization_form)
      |> assign(delete_user_form: delete_user_form)
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
end
