defmodule TuistWeb.App do
  @moduledoc """
  Does necessary preprocessing before showing an app view.
  """

  use TuistWeb, :live_view

  import Phoenix.Component

  alias Tuist.Accounts
  alias Tuist.Projects

  def on_mount(:mount_app, %{"owner" => owner_handle, "project" => project_handle}, session, socket)
      when is_binary(owner_handle) and is_binary(project_handle) do
    user_token = session["user_token"]

    user =
      if is_nil(user_token) do
        nil
      else
        Accounts.get_user_by_session_token(session["user_token"], preload: [:account])
      end

    TuistWeb.Authorization.require_user_can_read_project(%{
      user: user,
      account_handle: owner_handle,
      project_handle: project_handle
    })

    project =
      Projects.get_project_by_account_and_project_handles(owner_handle, project_handle)

    projects =
      if is_nil(user) do
        []
      else
        Projects.get_all_project_accounts(user)
      end

    {:cont,
     socket
     |> assign(:selected_account, owner_handle)
     |> assign(:selected_project, project)
     |> assign(:current_user, user)
     |> assign(
       :projects,
       projects
     )}
  end

  def on_mount(:mount_app, _params, _session, socket) do
    {:cont, socket}
  end
end
