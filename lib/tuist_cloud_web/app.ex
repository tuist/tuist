defmodule TuistCloudWeb.App do
  @moduledoc """
  Does necessary preprocessing before showing an app view.
  """

  use TuistCloudWeb, :live_view

  alias TuistCloud.Accounts
  alias TuistCloud.Authorization
  alias TuistCloud.Projects
  import Phoenix.Component

  def on_mount(:mount_app, %{"owner" => owner, "project" => project}, session, socket)
      when is_binary(owner) and is_binary(project) do
    user = Accounts.get_user_by_session_token(session["user_token"])
    account = user |> Accounts.get_account_from_user()

    project =
      Projects.get_project_by_account_and_project_name(owner, project)

    owner_account = Accounts.get_account_by_handle(owner)

    if is_nil(project) or is_nil(owner_account) or
         not Authorization.can(user, :read, owner_account, :project) do
      raise TuistCloudWeb.Errors.NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end

    {:cont,
     socket
     |> assign(:selected_owner, owner)
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

  def on_mount(:mount_app, _params, _session, socket) do
    {:cont, socket}
  end
end
