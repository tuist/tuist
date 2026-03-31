defmodule TuistWeb.DocsSelectorLive do
  @moduledoc """
  A small LiveView embedded in the docs layout for the account/project selector.
  Needed because the layout is a dead view and can't handle LiveView events.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppLayoutComponents, only: [headerbar_breadcrumbs: 1]

  alias Tuist.Accounts
  alias TuistWeb.AccountProjectBreadcrumbs

  def mount(_params, session, socket) do
    current_user =
      case session["current_user_id"] do
        nil -> nil
        user_id -> Accounts.get_user!(user_id, preload: [:account])
      end

    socket = assign(socket, :current_user, current_user)

    socket =
      if is_nil(current_user) do
        assign(socket, breadcrumbs: [], user_accounts: [], account_projects: [])
      else
        accounts = AccountProjectBreadcrumbs.get_user_accounts(current_user)
        selected_account = current_user.account
        projects = AccountProjectBreadcrumbs.get_account_projects(selected_account, current_user)
        selected_project = List.first(projects)

        socket
        |> assign(:user_accounts, accounts)
        |> assign(:selected_account, selected_account)
        |> assign(:account_projects, projects)
        |> assign(:selected_project, selected_project)
        |> build_breadcrumbs(selected_account, accounts, selected_project, projects)
      end

    {:ok, socket, layout: false}
  end

  def render(assigns) do
    ~H"""
    <div :if={@breadcrumbs != []} id="docs-selector-live">
      <.headerbar_breadcrumbs breadcrumbs={@breadcrumbs} id="docs-selector-breadcrumbs" />
    </div>
    """
  end

  def handle_event("select-account", %{"value" => account_id}, socket) do
    case Enum.find(socket.assigns.user_accounts, &(&1.id == account_id)) do
      nil ->
        {:noreply, socket}

      account ->
        current_user = socket.assigns[:current_user]
        projects = AccountProjectBreadcrumbs.get_account_projects(account, current_user)
        selected_project = List.first(projects)

        {:noreply,
         socket
         |> assign(:selected_account, account)
         |> assign(:account_projects, projects)
         |> assign(:selected_project, selected_project)
         |> build_breadcrumbs(account, socket.assigns.user_accounts, selected_project, projects)}
    end
  end

  def handle_event("select-project", %{"value" => project_id}, socket) do
    case Enum.find(socket.assigns.account_projects, &(&1.id == project_id)) do
      nil ->
        {:noreply, socket}

      project ->
        {:noreply,
         socket
         |> assign(:selected_project, project)
         |> build_breadcrumbs(
           socket.assigns.selected_account,
           socket.assigns.user_accounts,
           project,
           socket.assigns.account_projects
         )}
    end
  end

  defp build_breadcrumbs(socket, selected_account, accounts, selected_project, projects) do
    account_breadcrumb =
      AccountProjectBreadcrumbs.account_breadcrumb(selected_account, accounts, stateful: true)

    project_breadcrumb =
      AccountProjectBreadcrumbs.project_breadcrumb(selected_project, selected_account, projects, stateful: true)

    assign(socket, :breadcrumbs, [account_breadcrumb, project_breadcrumb])
  end
end
