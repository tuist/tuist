defmodule TuistWeb.API.OnceRunsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.OnceEvents.Query
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.OnceRun

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Once"]

  operation(:index,
    summary: "List Once runs for a project, newest first.",
    operation_id: "listOnceRuns",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      kind: [in: :query, type: OnceRun.kind(), description: "Filter by run kind."],
      status: [
        in: :query,
        type: %Schema{title: "OnceRunStatus", type: :string, enum: ["success", "failure"]},
        description: "Filter by the result of finalized runs."
      ],
      is_ci: [in: :query, type: :boolean, description: "Filter by whether the run happened on CI."],
      git_branch: [in: :query, type: :string, description: "Filter by git branch."],
      page_size: [
        in: :query,
        type: %Schema{
          title: "OnceRunsIndexPageSize",
          description: "The maximum number of runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "OnceRunsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok: {"List of Once runs", "application/json", OnceRun.list()},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    json(conn, Query.list_runs(project.id, Map.new(params, fn {key, value} -> {to_string(key), value} end)))
  end

  operation(:show,
    summary: "Get a Once run with its action totals, cache summary and, for test runs, test totals.",
    operation_id: "getOnceRun",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      once_run_id: [in: :path, type: :string, required: true, description: "The run ID, unique within the project."]
    ],
    responses: %{
      ok: {"Once run details", "application/json", OnceRun.detail()},
      not_found: {"Run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def show(%{assigns: %{selected_project: project}, params: %{once_run_id: run_id}} = conn, _params) do
    case Query.get_run(project.id, run_id) do
      {:ok, run} -> json(conn, run)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Run not found."})
    end
  end
end
