defmodule TuistWeb.OpsQALive do
  @moduledoc false
  use TuistWeb, :live_view

  import Ecto.Query

  alias Tuist.Projects.Project
  alias Tuist.QA.Run
  alias Tuist.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :projects_with_qa_runs, list_projects_with_qa_runs())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900">QA Operations</h1>
        <p class="mt-2 text-gray-600">Projects that have had QA runs</p>
      </div>

      <div class="bg-white shadow overflow-hidden sm:rounded-md">
        <ul role="list" class="divide-y divide-gray-200">
          <%= for project <- @projects_with_qa_runs do %>
            <li class="px-6 py-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="h-10 w-10 rounded-full bg-gray-300 flex items-center justify-center">
                      <span class="text-sm font-medium text-gray-700">
                        {String.first(project.account_name) |> String.upcase()}
                      </span>
                    </div>
                  </div>
                  <div class="ml-4">
                    <div class="flex items-center">
                      <p class="text-sm font-medium text-gray-900">
                        {project.account_name}/{project.name}
                      </p>
                      <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                        {project.qa_runs_count} QA runs
                      </span>
                    </div>
                    <%= if project.latest_qa_run_at do %>
                      <p class="text-sm text-gray-500">
                        Latest QA run: {format_datetime(project.latest_qa_run_at)}
                      </p>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center space-x-2">
                  <%= if project.latest_qa_run_status do %>
                    <span class={[
                      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                      case project.latest_qa_run_status do
                        "completed" -> "bg-green-100 text-green-800"
                        "running" -> "bg-yellow-100 text-yellow-800"
                        "failed" -> "bg-red-100 text-red-800"
                        _ -> "bg-gray-100 text-gray-800"
                      end
                    ]}>
                      {String.capitalize(project.latest_qa_run_status)}
                    </span>
                  <% end %>
                </div>
              </div>
            </li>
          <% end %>
        </ul>
        <%= if Enum.empty?(@projects_with_qa_runs) do %>
          <div class="text-center py-12">
            <div class="text-gray-500">
              <p class="text-lg font-medium">No QA runs found</p>
              <p class="mt-1">No projects have had QA runs yet.</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp list_projects_with_qa_runs do
    query =
      from(p in Project,
        join: pr in assoc(p, :previews),
        join: ab in assoc(pr, :app_builds),
        join: qa in Run,
        on: qa.app_build_id == ab.id,
        join: a in assoc(p, :account),
        group_by: [p.id, p.name, a.name],
        select: %{
          id: p.id,
          name: p.name,
          account_name: a.name,
          qa_runs_count: count(qa.id),
          latest_qa_run_at: max(qa.inserted_at),
          latest_qa_run_status:
            fragment(
              "
            (SELECT status 
             FROM qa_runs 
             JOIN app_builds ON qa_runs.app_build_id = app_builds.id 
             JOIN previews ON app_builds.preview_id = previews.id 
             WHERE previews.project_id = ? 
             ORDER BY qa_runs.inserted_at DESC 
             LIMIT 1)",
              p.id
            )
        },
        order_by: [desc: max(qa.inserted_at)]
      )

    Repo.all(query)
  end

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_datetime(_), do: "Unknown"
end
