defmodule Tuist.MCP.Components.Tools.GetBazelBuildStep do
  @moduledoc "Get a recorded Bazel profile interval with its action outcome and separately fetched sanitized log when published by Bazel. IDs are opaque and scoped to the invocation. Profile times are milliseconds relative to the profile start. Older builds fall back to bounded BEP summaries. Retention is 90 days."
  use Tuist.MCP.Tool,
    name: "get_bazel_build_step",
    title: "Get Bazel Build Step",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.BuildStep.input(:bazel, true),
    output_schema: Tuist.MCP.Components.Tools.BuildStep.detail(:bazel)

  alias Tuist.Bazel
  alias Tuist.Builds.RecordedSteps, as: Steps

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, args, project) do
    id = Map.get(args, "invocation_id")

    with {:ok, build} <- Bazel.get_invocation(project.id, id, include_cache_summary: false),
         {:ok, result} <- Steps.get(build, Map.get(args, "step_id")) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
    end
  end
end
