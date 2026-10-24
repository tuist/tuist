defmodule TuistWeb.ProjectOIDCSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.OIDC.ProjectProviders
  alias Tuist.OIDC.ScopeRules
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistWeb.Components.OIDCScopeRules

  @rules_id "project-oidc-scope-rules"

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_project: selected_project, current_user: current_user}} = socket) do
    if Authorization.authorize(:project_update, current_user, selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    project = Repo.preload(selected_project, vcs_connection: :github_app_installation)

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_projects", "OIDC")} · #{selected_project.name} · Tuist")
      |> assign(:has_vcs_connection, Projects.has_vcs_connection?(project))
      |> assign(:rules_id, @rules_id)
      |> assign(:oidc_rules, OIDCScopeRules.rules_by_scope(ScopeRules.list_project_rules(selected_project)))
      |> assign(:oidc_rule_errors, %{})
      |> assign(:unmatched_providers, ProjectProviders.recent_unmatched_providers(selected_project))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event(event, params, %{assigns: %{selected_project: project}} = socket)
      when event in ["save_oidc_rule", "delete_oidc_rule", "close_oidc_rule_modal"] do
    callbacks = %{
      id: @rules_id,
      put_rule: &ScopeRules.put_project_rule(project, &1, &2),
      delete_rule: &ScopeRules.delete_project_rule(project, &1),
      list_rules: fn -> ScopeRules.list_project_rules(project) end
    }

    {:noreply, OIDCScopeRules.handle_rule_event(event, params, socket, callbacks)}
  end
end
