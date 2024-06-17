defmodule TuistCloudWeb.App do
  @moduledoc """
  Does necessary preprocessing before showing an app view.
  """

  use TuistCloudWeb, :live_view

  alias TuistCloud.Accounts
  alias TuistCloud.Authorization
  alias TuistCloud.Projects
  import Phoenix.Component

  def on_mount(
        :mount_app,
        %{"owner" => owner_handle, "project" => project_handle},
        session,
        socket
      )
      when is_binary(owner_handle) and is_binary(project_handle) do
    user_token = session["user_token"]

    user =
      if is_nil(user_token) do
        nil
      else
        Accounts.get_user_by_session_token(session["user_token"], preloads: [:account])
      end

    TuistCloudWeb.Authorization.require_user_can_read_project(%{
      user: user,
      owner_handle: owner_handle,
      project_handle: project_handle
    })

    project =
      Projects.get_project_by_account_and_project_name(owner_handle, project_handle)

    owner_account = Accounts.get_account_by_handle(owner_handle)

    projects =
      if is_nil(user) do
        []
      else
        Projects.get_all_project_accounts(user)
      end

    {:cont,
     socket
     |> assign(:selected_owner, owner_handle)
     |> assign(:selected_project, project)
     |> assign(:current_user, user)
     |> assign(
       :projects,
       projects
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
