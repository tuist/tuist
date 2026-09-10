defmodule TuistWeb.API.GradleBuildStepsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds.RecordedSteps, as: Steps
  alias Tuist.Gradle
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
    title: "GradleBuildStep",
    type: :object,
    properties: @step_properties,
    required: [:id, :title, :project, :target, :category, :start_ms, :duration_ms, :status]
  }
  @detail %Schema{
    title: "GradleBuildStepDetail",
    type: :object,
    properties:
      Map.merge(@step_properties, %{log: %Schema{type: :string, nullable: true}, log_truncated: %Schema{type: :boolean}}),
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
    summary: "List recorded Gradle build steps without logs.",
    operation_id: "listGradleBuildSteps",
    description:
      "Recorded steps are retained for 90 days. IDs are opaque strings scoped to their parent. Time filters select overlaps; end_ms is exclusive. Gradle reports without a start timestamp use the first recorded timestamp as origin.",
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
            description: "Exact category returned by a recorded step."
          ],
          status: [
            in: :query,
            type: %Schema{
              type: :string,
              enum: ~w(success failure unknown local_hit remote_hit cache_hit up_to_date skipped no_source)
            }
          ],
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
           title: "GradleBuildStepsList",
           type: :object,
           properties: %{
             steps: %Schema{type: :array, items: @step},
             pagination_metadata: PaginationMetadata,
             time_origin: %Schema{type: :string, enum: ["build_start", "first_recorded_timestamp"]},
             coverage: %Schema{type: :string, enum: ["recorded_operations", "retained_action_spans"]},
             availability: %Schema{type: :string, enum: ["available", "processing", "unavailable"]}
           },
           required: [:steps, :pagination_metadata, :availability, :time_origin, :coverage]
         }}
      )
  )

  def index(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    with {:ok, build} <- Gradle.get_build(params.build_id, project_id: project.id),
         {:ok, result} <- Steps.list(build, params) do
      json(conn, result)
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:show,
    summary: "Get one recorded Gradle build step.",
    operation_id: "getGradleBuildStep",
    description: "Returns recorded metadata. Per-step logs are not collected for Gradle; log is null.",
    parameters:
      @path_params ++
        [
          step_id: [
            in: :path,
            type: %Schema{type: :string, maxLength: 128},
            required: true,
            description: "The opaque ID returned by listGradleBuildSteps."
          ]
        ],
    responses: Map.put(@errors, :ok, {"Recorded step metadata", "application/json", @detail})
  )

  def show(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    with {:ok, build} <- Gradle.get_build(params.build_id, project_id: project.id),
         {:ok, step} <- Steps.get(build, params.step_id) do
      json(conn, step)
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, :not_found), do: conn |> put_status(:not_found) |> json(%{message: "Build or step not found."})

  defp error(conn, _reason),
    do: conn |> put_status(:bad_request) |> json(%{message: "Invalid step ID, filters, or time range."})
end
