defmodule TuistCloudWeb.App do
  @moduledoc """
  Does necessary preprocessing before showing an app view.
  """

  use TuistCloudWeb, :live_view

  alias TuistCloud.Accounts
  alias TuistCloud.Authorization
  alias TuistCloud.Projects
  import Phoenix.Component

  def on_mount(:mount_app, params, session, socket) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    account = selected_account(user)

    if is_nil(params["owner"]) or is_nil(params["project"]) do
      if is_nil(user.last_visited_project_id) do
        project_accounts = Projects.get_all_project_accounts(user)

        redirect_to_project(project_accounts, socket)
      else
        project_account = Projects.get_project_account_by_project_id(user.last_visited_project_id)

        {:halt,
         redirect(socket,
           to: ~p"/#{project_account.account.name}/#{project_account.project.name}"
         )}
      end
    else
      project =
        Projects.get_project_by_account_and_project_name(params["owner"], params["project"])

      owner_account = Accounts.get_account_by_handle(params["owner"])

      {:cont,
       socket
       |> assign(:current_owner, params["owner"])
       |> assign(:selected_project, project)
       |> assign(:current_user, user)
       |> assign(:selected_account, account)
       |> assign(
         :projects,
         Projects.get_all_project_accounts(user)
       )
       |> assign(
         :can_update_billing,
         Authorization.can(user, :update, owner_account, :billing)
       )}
    end
  end

  defp selected_account(user) do
    user |> Accounts.get_account_from_user()
  end

  defp redirect_to_project(project_accounts, socket) do
    if Enum.empty?(project_accounts) do
      {:halt, redirect(socket, to: ~p"/get-started")}
    else
      project_account = hd(project_accounts)

      {:halt,
       redirect(socket,
         to: ~p"/#{project_account.account.name}/#{project_account.project.name}"
       )}
    end
  end
end
