defmodule Tuist.MCP.Components.Tools.GetBazelRemoteAction do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "get_bazel_remote_action",
    title: "Get Bazel Remote Action",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema:
      Tuist.MCP.Components.Tools.BazelRemoteAction.input(
        %{"action_id" => %{"type" => "string", "description" => "The `id` from list_bazel_remote_actions."}},
        ["action_id"]
      ),
    output_schema: Tuist.MCP.Components.Tools.BazelRemoteAction.schema()

  alias Tuist.Bazel
  alias Tuist.RemoteExecution.Actions

  @impl EMCP.Tool
  def description do
    "Get one action Tuist remote execution ran for a Bazel invocation: its argv, environment (secret-looking values masked), platform, working directory, output paths, worker, exit code, the first 16 KiB of stdout and stderr, compiler `errors` recognised in stderr, phase timings and action digest."
  end

  def execute(_conn, %{"invocation_id" => invocation_id, "action_id" => action_id}, project) do
    with {:ok, invocation} <- Bazel.get_invocation(project.id, invocation_id, include_cache_summary: false),
         {:ok, action} <- Actions.get(project.id, invocation.invocation_id, action_id) do
      {:ok, Actions.json(action)}
    else
      {:error, :not_found} -> {:error, "Remote action not found: #{action_id}"}
    end
  end
end
