defmodule AtlasWeb.Engineering.ProjectsLive do
  @moduledoc """
  Lists engineering projects and renders per-project detail.

  Ported from Hive's `HiveWeb.ProjectLive.Index` + `.Show` with the
  Hive-specific side panels (Drops, Specs, Grafana, Alerts) stripped.
  The remaining surface is: list projects, show a project's name,
  description, visibility, linked domains, and linked repositories.
  """

  use AtlasWeb, :live_view

  alias Atlas.Engineering.Projects

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Projects"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    projects = Projects.list_visible_projects(socket.assigns[:current_user])
    assign(socket, projects: projects)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    case Projects.fetch_visible_project(id, socket.assigns[:current_user]) do
      {:ok, project} ->
        socket
        |> assign(:project, project)
        |> assign(:page_title, project.name)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Project not found."))
        |> push_navigate(to: ~p"/engineering/projects")
    end
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-semibold">{gettext("Projects")}</h1>

      <div class="mt-6 space-y-3">
        <%= for project <- @projects do %>
          <div class="border rounded p-4 hover:bg-neutral-50">
            <.link navigate={~p"/engineering/projects/#{project.id}"} class="font-medium">
              {project.name}
            </.link>
            <p :if={project.description} class="text-sm text-neutral-500 mt-1">
              {project.description}
            </p>
            <p class="text-xs text-neutral-400 mt-2">{project.visibility}</p>
          </div>
        <% end %>

        <p :if={@projects == []} class="text-sm text-neutral-500">
          {gettext("No projects yet.")}
        </p>
      </div>
    </div>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="p-8 space-y-6">
      <div>
        <.link navigate={~p"/engineering/projects"} class="text-sm text-neutral-500">
          &larr; {gettext("Projects")}
        </.link>
        <h1 class="text-2xl font-semibold mt-2">{@project.name}</h1>
        <p :if={@project.description} class="text-neutral-500">{@project.description}</p>
      </div>

      <section>
        <h2 class="text-lg font-medium">{gettext("Linked domains")}</h2>
        <ul class="mt-2 space-y-1">
          <%= for domain <- @project.domains do %>
            <li>
              <.link navigate={~p"/engineering/domains/#{domain.id}"}>{domain.name}</.link>
            </li>
          <% end %>
          <li :if={@project.domains == []} class="text-sm text-neutral-500">
            {gettext("No domains linked.")}
          </li>
        </ul>
      </section>

      <section>
        <h2 class="text-lg font-medium">{gettext("Repositories")}</h2>
        <ul class="mt-2 space-y-1">
          <%= for repo <- @project.github_repositories do %>
            <li class="text-sm">{repo.owner}/{repo.name}</li>
          <% end %>
          <li :if={@project.github_repositories == []} class="text-sm text-neutral-500">
            {gettext("No repositories linked.")}
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
