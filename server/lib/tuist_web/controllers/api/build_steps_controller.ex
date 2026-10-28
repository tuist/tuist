defmodule TuistWeb.API.BuildStepsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias Tuist.Builds.Steps
  alias TuistWeb.API.Schemas.Builds.BuildStep
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug)
  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  @step BuildStep.step("XcodeBuildStep")
  @detail BuildStep.detail("XcodeBuildStepDetail", false)
  @path_params [
    account_handle: [in: :path, type: :string, required: true, description: "Account handle."],
    project_handle: [in: :path, type: :string, required: true, description: "Project handle."],
    build_id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true, description: "Build ID."]
  ]
  @errors BuildStep.errors()

  operation(:index,
    summary: "List recorded Xcode build steps without logs.",
    operation_id: "listXcodeBuildSteps",
    description:
      "Steps are retained for 90 days. Times are milliseconds from build start. Step IDs are decimal strings preserving UInt64 precision. Unavailable means steps were not recorded or have expired. Time filters select overlapping steps; end_ms is exclusive.",
    parameters:
      @path_params ++
        BuildStep.query_parameters(~w(success failure)),
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

  defp error(conn, reason), do: BuildStep.error(conn, reason)
end
