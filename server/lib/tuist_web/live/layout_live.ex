defmodule TuistWeb.LayoutLive do
  @moduledoc """
  Does necessary preprocessing before showing an app view.
  """

  use TuistWeb, :live_view

  import Phoenix.Component
  import TuistWeb.AppLayoutComponents

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.CommandEvents
  alias Tuist.GitHub.Releases
  alias Tuist.Projects
  alias TuistWeb.Errors.NotFoundError

  def on_mount(
        :optional_project,
        %{"account_handle" => account_handle, "project_handle" => project_handle} = params,
        session,
        socket
      ) do
    selected_project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle, preload: [:account])

    socket = assign(socket, :selected_project, selected_project)

    if TuistWeb.Authentication.authenticated?(socket.assigns) or
         selected_project.visibility == :public do
      on_mount(:project, params, session, socket)
    else
      {:cont, socket}
    end
  end

  def on_mount(
        :project,
        %{"account_handle" => account_handle, "project_handle" => project_handle} = params,
        session,
        socket
      )
      when is_binary(account_handle) and is_binary(project_handle) do
    current_user = get_current_user(session)

    TuistWeb.Authorization.require_user_can_read_project(%{
      user: current_user,
      account_handle: account_handle,
      project_handle: project_handle
    })

    selected_project =
      Map.get(
        socket.assigns,
        :selected_project,
        Projects.get_project_by_account_and_project_handles(account_handle, project_handle, preload: [:account])
      )

    if is_nil(selected_project) do
      raise NotFoundError,
            dgettext("dashboard", "The project you are looking for doesn't exist or has been moved.")
    end

    %{account: selected_account} = selected_project

    selected_projects = get_projects(selected_account, current_user)

    current_user_accounts =
      if is_nil(current_user) do
        []
      else
        get_user_organization_accounts(current_user) ++ [current_user.account]
      end

    {:cont,
     socket
     |> assign_current_path()
     |> append_breadcrumb(%{
       label: selected_account.name,
       icon: "smart_home",
       show_avatar: true,
       avatar_color: Accounts.avatar_color(selected_account),
       items:
         Enum.map(current_user_accounts, fn account ->
           %{
             label: account.name,
             value: account.id,
             selected: account.id == selected_account.id,
             href: ~p"/#{account.name}/projects",
             show_avatar: true,
             avatar_color: Accounts.avatar_color(account)
           }
         end) ++
           [
             %{
               label: dgettext("dashboard", "Create organization"),
               value: "create-organization",
               href: ~p"/organizations/new",
               icon: "building_plus",
               selected: false
             }
           ]
     })
     |> append_breadcrumb(%{
       label: selected_project.name,
       items:
         Enum.map(selected_projects, fn project ->
           %{
             label: project.name,
             value: project.id,
             selected: selected_project.id == project.id,
             href: ~p"/#{account_handle}/#{project.name}"
           }
         end)
     })
     |> assign_latest_app_release()
     |> assign_latest_cli_release()
     |> assign(:selected_account, selected_account)
     |> assign(:selected_project, selected_project)
     |> assign(:current_user, current_user)
     |> assign(
       :selected_projects,
       selected_projects
     )
     |> assign_selected_run(params)}
  end

  def on_mount(:account, params, session, socket) do
    current_user = get_current_user(session)

    current_user_accounts =
      get_user_organization_accounts(current_user) ++ [current_user.account]

    selected_account =
      case Map.get(params, "account_handle") do
        handle when is_binary(handle) -> Accounts.get_account_by_handle(handle)
        _ -> current_user.account
      end

    if is_nil(selected_account) do
      raise NotFoundError,
            dgettext("dashboard", "The account you are looking for doesn't exist or has been moved.")
    end

    {:cont,
     socket
     |> assign_current_path()
     |> append_breadcrumb(%{
       label: selected_account.name,
       show_avatar: true,
       avatar_color: Accounts.avatar_color(selected_account),
       items:
         Enum.map(current_user_accounts, fn account ->
           %{
             label: account.name,
             value: account.id,
             href: ~p"/#{account.name}/projects",
             selected: account.id == selected_account.id,
             show_avatar: true,
             avatar_color: Accounts.avatar_color(account)
           }
         end) ++
           [
             %{
               label: dgettext("dashboard", "Create organization"),
               value: "create-organization",
               href: ~p"/organizations/new",
               icon: "building_plus",
               selected: false
             }
           ]
     })
     |> assign(
       :can_read_billing,
       Authorization.authorize(:billing_read, current_user, selected_account) == :ok
     )
     |> assign_latest_app_release()
     |> assign_latest_cli_release()
     |> assign(:selected_account, selected_account)
     |> assign(:current_user, current_user)
     |> assign(:current_user_accounts, current_user_accounts)}
  end

  def on_mount(:ops, _params, session, socket) do
    current_user = get_current_user(session)

    {:cont,
     socket
     |> assign_current_path()
     |> assign_latest_app_release()
     |> assign_latest_cli_release()
     |> assign(:current_user, current_user)}
  end

  defp get_user_organization_accounts(user) do
    if is_nil(user) do
      []
    else
      user |> Accounts.get_user_organization_accounts() |> Enum.map(& &1.account)
    end
  end

  defp assign_current_path(socket) do
    attach_hook(socket, :assign_current_path, :handle_params, fn _params, url, socket ->
      %{path: current_path} = URI.parse(url)
      {:cont, assign(socket, :current_path, current_path)}
    end)
  end

  defp get_projects(account, current_user) do
    account
    |> Projects.get_all_project_accounts()
    |> Enum.filter(fn %{account: account, project: project} ->
      Authorization.authorize(:project_url_access, current_user, %{project | account: account}) == :ok
    end)
    |> Enum.map(&%{&1.project | account: &1.account})
  end

  defp get_current_user(session) do
    user_token = session["user_token"]

    user =
      if is_nil(user_token) do
        nil
      else
        Accounts.get_user_by_session_token(session["user_token"], preload: [:account])
      end

    user
  end

  defp assign_selected_run(socket, params) do
    if is_nil(params["run_id"]) do
      assign(socket, :selected_run, nil)
    else
      case CommandEvents.get_command_event_by_id(params["run_id"]) do
        {:ok, run} ->
          assign(socket, :selected_run, run)

        {:error, :not_found} ->
          raise NotFoundError,
                dgettext("dashboard", "The run you are looking for doesn't exist or has been moved.")
      end
    end
  end

  def assign_latest_app_release(socket) do
    assign_async(socket, :latest_app_release, &get_latest_app_release/0)
  end

  defp get_latest_app_release do
    latest_app_release = Releases.get_latest_app_release()

    latest_app_release =
      if not is_nil(latest_app_release) do
        latest_app_release.assets
        |> Enum.find(&String.ends_with?(&1.browser_download_url, "dmg"))
        |> Map.get(:browser_download_url)
      end

    {:ok, %{latest_app_release: latest_app_release}}
  end

  def assign_latest_cli_release(socket) do
    assign_async(socket, :latest_cli_release, &get_latest_cli_release/0)
  end

  defp get_latest_cli_release do
    latest_cli_release = Releases.get_latest_cli_release()

    latest_cli_release =
      if not is_nil(latest_cli_release) do
        %{published_at: published_at} = latest_cli_release

        if Timex.after?(published_at, Timex.shift(Timex.today(), days: -1)),
          do: latest_cli_release
      end

    {:ok, %{latest_cli_release: latest_cli_release}}
  end
end
