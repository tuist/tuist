defmodule TuistWeb.API.RemoteExecutionInsightsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias Tuist.RemoteExecution.Query
  alias Tuist.RemoteExecution.Schemas
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Remote execution"]

  @path_params [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]

  operation(:activity,
    summary: "List the project's remote actions running and queued right now.",
    operation_id: "getRemoteExecutionActivity",
    description:
      "A snapshot of the account's execution scheduler. Actions the execution gateway runs on a VM it holds in advance are not listed; they appear in usage once they finish.",
    parameters: @path_params,
    responses: %{
      ok: {"Running and queued actions", "application/json", Schemas.activity()},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      service_unavailable: {"The scheduler did not answer; retry shortly", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def activity(%{assigns: %{selected_project: project}} = conn, _params) do
    case Query.activity(project) do
      {:ok, activity} ->
        json(conn, activity)

      {:error, :unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{message: "Remote execution activity is unavailable. Retry shortly."})
    end
  end

  operation(:usage,
    summary: "Get the project's remote execution usage over a period.",
    operation_id: "getRemoteExecutionUsage",
    description:
      "Executions and measured execution time, in total, per VM shape, per dispatch mode and per hour, day or month. The period defaults to the last 30 days and spans at most #{Query.max_days()} days.",
    parameters:
      @path_params ++
        Enum.map(Schemas.usage_inputs(), fn {key, schema} -> {key, [in: :query, type: schema]} end),
    responses: %{
      ok: {"Remote execution usage", "application/json", Schemas.usage()},
      bad_request: {"The period is invalid", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def usage(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    case Query.usage(project, Map.take(params, [:from, :to])) do
      {:ok, usage} ->
        json(conn, usage)

      {:error, :invalid_period} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Use an ordered period of at most #{Query.max_days()} days."})
    end
  end
end
