defmodule TuistWeb.ProjectAuthenticationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.FlyOIDCTrustPolicy
  alias TuistWeb.Errors.UnauthorizedError
  alias TuistWeb.Helpers.OpenGraph

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_project: project, current_user: user}} = socket) do
    authorize_project_update!(user, project)

    socket =
      socket
      |> assign(fly_oidc_trust_policies: Projects.list_fly_oidc_trust_policies(project))
      |> assign(fly_oidc_form: to_form(FlyOIDCTrustPolicy.changeset(%{})))
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Authentication")} · #{project.name} · Tuist")
      |> assign(
        OpenGraph.project_image_assigns(project,
          title: dgettext("dashboard_projects", "Authentication"),
          fallback: "settings"
        )
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create_fly_oidc_trust_policy", %{"fly_oidc_trust_policy" => attrs}, socket) do
    project = authorize_project_update!(socket)

    case Projects.create_fly_oidc_trust_policy(project, attrs) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> assign(fly_oidc_trust_policies: Projects.list_fly_oidc_trust_policies(project))
         |> assign(fly_oidc_form: to_form(FlyOIDCTrustPolicy.changeset(%{})))
         |> put_flash(:info, dgettext("dashboard_projects", "Fly.io trust policy added."))}

      {:error, changeset} ->
        {:noreply, assign(socket, fly_oidc_form: to_form(changeset))}
    end
  end

  def handle_event("delete_fly_oidc_trust_policy", %{"policy-id" => policy_id}, socket) do
    project = authorize_project_update!(socket)

    case Projects.delete_fly_oidc_trust_policy(project, policy_id) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> assign(fly_oidc_trust_policies: Projects.list_fly_oidc_trust_policies(project))
         |> put_flash(:info, dgettext("dashboard_projects", "Fly.io trust policy removed."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_projects", "Trust policy not found."))}
    end
  end

  defp authorize_project_update!(socket) do
    project = Projects.get_project_by_id(socket.assigns.selected_project.id)
    authorize_project_update!(socket.assigns.current_user, project)
    project
  end

  defp authorize_project_update!(user, project) do
    if Authorization.authorize(:project_update, user, project) != :ok do
      raise UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end
  end
end
