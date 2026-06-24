defmodule TuistWeb.AccountSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component

  alias Phoenix.HTML.Form
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Authorization
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

    preferred_locale_form =
      to_form(%{"preferred_locale" => current_user.preferred_locale || "browser"})

    socket =
      socket
      |> assign(rename_account_form: rename_account_form)
      |> assign(delete_organization_form: delete_organization_form)
      |> assign(delete_user_form: delete_user_form)
      |> assign(region_form: region_form)
      |> assign(preferred_locale_form: preferred_locale_form)
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
end
