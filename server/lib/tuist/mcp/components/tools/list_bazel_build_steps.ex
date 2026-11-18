defmodule Tuist.MCP.Components.Tools.ListBazelBuildSteps do
  @moduledoc "Recorded Bazel profile intervals with action outcomes. Set remote_execution=true for actions with correlated server queue, input-fetch, execution and output-upload timings. Phase milliseconds sum recorded attempts within each action; null or absent means unavailable, not zero. These are profile observations, not billed usage or proof of fresh execution; cached server results can carry execution metadata. Upload-only client spans are excluded. IDs are opaque and invocation-scoped. Profile times are relative to profile start; time filters select overlaps. Older builds fall back to bounded BEP summaries unless remote_execution=true. Retention is 90 days. Sanitized logs are fetched separately with get_bazel_build_step."
  use Tuist.MCP.Tool,
    name: "list_bazel_build_steps",
    title: "List Bazel Build Steps",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.BuildStep.input(:bazel, false),
    output_schema: Tuist.MCP.Components.Tools.BuildStep.list(:bazel)

  alias Tuist.Bazel
  alias Tuist.Builds.RecordedSteps, as: Steps

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, args, project) do
    id = Map.get(args, "invocation_id")

    with {:ok, build} <- Bazel.get_invocation(project.id, id, include_cache_summary: false),
         {:ok, result} <- Steps.list(build, args) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
    end
  end
end
