defmodule TuistWeb.API.BuildStepsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias Tuist.Builds.Steps
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug)
  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  @step_properties %{
    id: %Schema{type: :string},
    title: %Schema{type: :string},
    project: %Schema{type: :string},
    target: %Schema{type: :string},
    category: %Schema{type: :string},
    start_ms: %Schema{type: :number},
    duration_ms: %Schema{type: :number},
    status: %Schema{type: :string}
  }
  @step %Schema{
    title: "XcodeBuildStep",
    type: :object,
    properties: @step_properties,
    required: [:id, :title, :project, :target, :category, :start_ms, :duration_ms, :status]
  }
  @detail %Schema{
    title: "XcodeBuildStepDetail",
    type: :object,
    properties: Map.merge(@step_properties, %{log: %Schema{type: :string}, log_truncated: %Schema{type: :boolean}}),
    required: [:id, :title, :project, :target, :category, :start_ms, :duration_ms, :status, :log, :log_truncated]
  }
  @path_params [
    account_handle: [in: :path, type: :string, required: true, description: "Account handle."],
    project_handle: [in: :path, type: :string, required: true, description: "Project handle."],
    build_id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true, description: "Build ID."]
  ]
  @errors %{
    bad_request: {"Invalid step ID, filters, or time range", "application/json", Error},
    not_found: {"Build or step not found", "application/json", Error},
    forbidden: {"Access denied", "application/json", Error},
    too_many_requests: Responses.authorization_throttled()
  }

  operation(:index,
    summary: "List recorded Xcode build steps without logs.",
    operation_id: "listXcodeBuildSteps",
    description:
      "Steps are retained for 90 days. Times are milliseconds from build start. Step IDs are decimal strings preserving UInt64 precision. Unavailable means steps were not recorded or have expired. Time filters select overlapping steps; end_ms is exclusive.",
    parameters:
      @path_params ++
        [
          page: [in: :query, type: %Schema{type: :integer, minimum: 1, maximum: 100_000, default: 1}],
          page_size: [in: :query, type: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}],
          search: [
            in: :query,
            type: %Schema{type: :string, maxLength: 512},
            description: "Case-insensitive title, project, or target search."
          ],
          project: [in: :query, type: %Schema{type: :string, maxLength: 512}],
          target: [in: :query, type: %Schema{type: :string, maxLength: 512}],
          category: [
            in: :query,
            type: %Schema{type: :string, maxLength: 128},
            description: "Exact recorded category, such as swiftCompilation."
          ],
          status: [in: :query, type: %Schema{type: :string, enum: ["success", "failure"]}],
          start_ms: [in: :query, type: %Schema{type: :number, minimum: 0}],
          end_ms: [in: :query, type: %Schema{type: :number, minimum: 0}],
          sort_by: [
            in: :query,
            type: %Schema{type: :string, enum: ["duration_ms", "start_ms"], default: "duration_ms"},
            description: "Duration descending or start time ascending; ties use step ID ascending."
          ]
        ],
    responses:
      Map.put(
        @errors,
        :ok,
        {"Recorded steps", "application/json",
         %Schema{
           title: "XcodeBuildStepsList",
           type: :object,
           properties: %{
             steps: %Schema{type: :array, items: @step},
             pagination_metadata: PaginationMetadata,
             availability: %Schema{type: :string, enum: ["available", "processing", "unavailable"]}
           },
           required: [:steps, :pagination_metadata, :availability]
         }}
      )
  )

  def index(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    with {:ok, build} <- Builds.get_build(params.build_id, project_id: project.id),
         true <- build.project_id == project.id,
         {:ok, result} <- Steps.list(build, params) do
      json(conn, result)
    else
      {:error, reason} -> error(conn, reason)
      false -> error(conn, :not_found)
    end
  end

  operation(:show,
    summary: "Get one recorded Xcode build step and its log.",
    operation_id: "getXcodeBuildStep",
    description:
      "Logs retain up to 64 KiB per step, with log_truncated indicating omitted output. Steps and logs expire after 90 days. An empty log means no output was recorded.",
    parameters:
      @path_params ++
        [
          step_id: [
            in: :path,
            type: %Schema{type: :string, pattern: "^[0-9]{1,20}$"},
            required: true,
            description: "The decimal string ID returned by listXcodeBuildSteps."
          ]
        ],
    responses: Map.put(@errors, :ok, {"Step details and log", "application/json", @detail})
  )

  def show(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    with {:ok, build} <- Builds.get_build(params.build_id, project_id: project.id),
         true <- build.project_id == project.id,
         {:ok, step} <- Steps.get(build.id, params.step_id) do
      json(conn, step)
    else
      {:error, reason} -> error(conn, reason)
      false -> error(conn, :not_found)
    end
  end

  defp error(conn, :not_found), do: conn |> put_status(:not_found) |> json(%{message: "Build or step not found."})

  defp error(conn, _reason),
    do: conn |> put_status(:bad_request) |> json(%{message: "Invalid step ID, filters, or time range."})
end
