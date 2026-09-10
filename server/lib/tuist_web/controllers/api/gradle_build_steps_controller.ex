defmodule TuistWeb.API.GradleBuildStepsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds.RecordedSteps, as: Steps
  alias Tuist.Gradle
  alias TuistWeb.API.Schemas.Builds.BuildStep
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug)
  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  @step BuildStep.step("GradleBuildStep")
  @detail BuildStep.detail("GradleBuildStepDetail", true)
  @path_params [
    account_handle: [in: :path, type: :string, required: true, description: "Account handle."],
    project_handle: [in: :path, type: :string, required: true, description: "Project handle."],
    build_id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true, description: "Build ID."]
  ]
  @errors BuildStep.errors()

  operation(:index,
    summary: "List recorded Gradle build steps without logs.",
    operation_id: "listGradleBuildSteps",
    description:
      "Recorded steps are retained for 90 days. IDs are opaque strings scoped to their parent. Time filters select overlaps; end_ms is exclusive. Gradle reports without a start timestamp use the first recorded timestamp as origin.",
    parameters:
      @path_params ++
        BuildStep.query_parameters(
          ~w(success failure unknown local_hit remote_hit cache_hit up_to_date skipped no_source)
        ),
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

  defp error(conn, reason), do: BuildStep.error(conn, reason)
end
