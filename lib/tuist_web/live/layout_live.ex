defmodule TuistWeb.LayoutLive do
  @moduledoc """
  Does necessary preprocessing before showing an app view.
  """

  use TuistWeb, :live_view

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Github
  import Phoenix.Component
  import TuistWeb.AppLayoutComponents

  def on_mount(
        :project,
        %{"account_handle" => account_handle, "project_handle" => project_handle},
        session,
        socket
      )
      when is_binary(account_handle) and is_binary(project_handle) do
    current_user = session |> get_current_user()

    TuistWeb.Authorization.require_user_can_read_project(%{
      user: current_user,
      account_handle: account_handle,
      project_handle: project_handle
    })

    project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle,
        preloads: [:account]
      )

    if is_nil(project) do
      raise TuistWeb.Errors.NotFoundError,
            gettext("The project you are looking for doesn't exist or has been moved.")
    end

    %{account: selected_account} = project

    selected_account_projects = selected_account |> get_account_projects(current_user)

    {:cont,
     socket
     |> assign_current_path()
     |> append_breadcrumb(%{content: selected_account.name})
     |> append_breadcrumb(%{
       content: project.name,
       items:
         selected_account_projects
         |> Enum.map(fn project ->
           %{content: project.name, href: ~p"/#{account_handle}/#{project.name}"}
         end)
     })
     |> assign_most_recent_release()
     |> assign(:selected_account, selected_account)
     |> assign(:selected_project, project)
     |> assign(:current_user, current_user)
     |> assign(
       :selected_account_projects,
       selected_account_projects
     )}
  end

  def on_mount(:account, params, session, socket) do
    current_user = session |> get_current_user()

    current_user_accounts =
      (current_user |> get_user_organization_accounts()) ++ [current_user.account]

    selected_account =
      case Map.get(params, "account_handle") do
        handle when is_binary(handle) -> Accounts.get_account_by_handle(handle)
        _ -> current_user.account
      end

    if is_nil(selected_account) do
      raise TuistWeb.Errors.NotFoundError,
            gettext("The account you are looking for doesn't exist or has been moved.")
    end

    {:cont,
     socket
     |> assign_current_path()
     |> append_breadcrumb(%{
       content: selected_account.name,
       items:
         current_user_accounts
         |> Enum.map(fn account ->
           %{content: account.name, href: ~p"/#{account.name}/projects"}
         end)
     })
     |> assign(
       :can_read_billing,
       Authorization.can(current_user, :read, selected_account, :billing)
     )
     |> assign_most_recent_release()
     |> assign(:selected_account, selected_account)
     |> assign(:current_user, current_user)
     |> assign(:current_user_accounts, current_user_accounts)}
  end

  defp get_user_organization_accounts(user) do
    if is_nil(user) do
      []
    else
      Accounts.get_user_organization_accounts(user) |> Enum.map(& &1.account)
    end
  end

  defp assign_current_path(socket) do
    socket
    |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
      %{path: current_path} = URI.parse(url)
      {:cont, socket |> assign(:current_path, current_path)}
    end)
  end

  defp get_account_projects(account, current_user) do
    Projects.get_all_project_accounts(account)
    |> Enum.filter(fn %{account: account, project: project} ->
      Authorization.can(current_user, :access, %{project | account: account}, :url)
    end)
    |> Enum.map(&%{&1.project | account: &1.account})
  end

  defp get_current_user(session) do
    user_token = session["user_token"]

    user =
      if is_nil(user_token) do
        nil
      else
        Accounts.get_user_by_session_token(session["user_token"], preloads: [:account])
      end

    user
  end

  def assign_most_recent_release(socket) do
    assign_async(socket, :most_recent_release, fn ->
      %{published_at: published_at} =
        most_recent_release = Github.get_most_recent_cli_release()

      most_recent_release =
        if Timex.after?(published_at, Timex.shift(Timex.today(), days: -1)),
          do: most_recent_release,
          else: nil

      {:ok, %{most_recent_release: most_recent_release}}
    end)
  end
end
