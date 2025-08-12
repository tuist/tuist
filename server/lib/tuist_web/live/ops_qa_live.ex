defmodule TuistWeb.OpsQALive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query

  alias Tuist.Projects.Project
  alias Tuist.QA.Run
  alias Tuist.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:projects_with_qa_runs, list_projects_with_qa_runs())
     |> assign(:head_title, "#{gettext("QA Operations")} · Tuist")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="qa-operations">
      <div data-part="row">
        <h2 data-part="title">{gettext("QA Operations")}</h2>
      </div>

      <div :if={Enum.empty?(@projects_with_qa_runs)} data-part="empty-state">
        <div data-part="content">
          <span data-part="title">{gettext("No QA runs found")}</span>
          <span data-part="description">{gettext("No projects have had QA runs yet.")}</span>
        </div>
      </div>

      <div :if={Enum.any?(@projects_with_qa_runs)} data-part="grid">
        <div :for={project <- @projects_with_qa_runs} data-part="project">
          <.project_background />
          <div data-part="title">
            {project.account_name}/{project.name}
          </div>
          <div data-part="platforms">
            <h3>{gettext("QA Information")}</h3>
            <div data-part="tags">
              <.tag label={
                ngettext("1 QA run", "%{count} QA runs", project.qa_runs_count,
                  count: project.qa_runs_count
                )
              } />
              <%= if project.latest_qa_run_status do %>
                <.tag label={String.capitalize(project.latest_qa_run_status)} />
              <% end %>
            </div>
          </div>
          <span :if={project.latest_qa_run_at} data-part="time">
            {gettext("Latest QA run: %{time}", %{time: format_datetime(project.latest_qa_run_at)})}
          </span>
          <span :if={!project.latest_qa_run_at} data-part="time">
            {gettext("No recent QA runs")}
          </span>
        </div>
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

  defp project_background(assigns) do
    ~H"""
    <svg viewBox="0 0 292 196" fill="none" xmlns="http://www.w3.org/2000/svg" data-part="background">
      <mask
        id="mask0_1989_22018"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="-1"
        width="292"
        height="198"
      >
        <rect
          x="0.5"
          y="-0.5"
          width="291"
          height="197"
          fill="url(#paint0_radial_1989_22018)"
          fill-opacity="0.2"
        />
      </mask>
      <g mask="url(#mask0_1989_22018)">
        <path d="M11 149.75H281" />
        <path d="M11 98H281" />
        <path d="M11 46.25H281" />
        <path d="M197.751 233V-37" />
        <path d="M146 233V-37" />
        <path d="M94.2501 233V-37" />
        <path d="M281 233L11 -37" />
        <path d="M11 233L281 -37" />
        <rect x="29" y="-19" width="234" height="234" />
        <circle cx="146" cy="98" r="51.75" />
        <circle cx="146" cy="98" r="74.25" />
        <circle cx="146" cy="98" r="117" />
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_1989_22018"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(146 98) rotate(90) scale(99 146)"
        >
          <stop stop-color="white" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end
end
