defmodule TuistWeb.ProjectIntegrationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects

  @impl true
  def mount(_params, _uri, %{assigns: assigns} = socket) do
    if Authorization.authorize(:project_update, assigns.current_user, assigns.selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    {:ok,
     assign(
       socket,
       :head_title,
       "#{dgettext("dashboard_projects", "Integrations")} · #{assigns.selected_project.name} · Tuist"
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_vcs_comments", %{"checked" => checked}, %{assigns: assigns} = socket)
      when is_boolean(checked) do
    case Authorization.authorize(:project_update, assigns.current_user, assigns.selected_project) do
      :ok ->
        project = Projects.get_project_by_id(assigns.selected_project.id)

        case Projects.update_project(project, %{vcs_comments_enabled: checked}) do
          {:ok, project} -> {:noreply, assign(socket, selected_project: project)}
          {:error, _} -> {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end
end
