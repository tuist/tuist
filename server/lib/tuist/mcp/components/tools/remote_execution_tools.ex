defmodule Tuist.MCP.Components.Tools.GetRemoteExecutionActivity do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_remote_execution_activity",
    title: "Get Remote Execution Activity",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."}
      },
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: Tuist.MCP.Tool.json_schema(Tuist.RemoteExecution.Schemas.activity())

  alias Tuist.RemoteExecution.Query

  @impl EMCP.Tool
  def description do
    "List a project's running Bazel invocations and the remote execution actions running and queued right now, with each action's invocation, mnemonic, target, digest, VM shape and time in its state. Actions the execution gateway runs on a VM it holds in advance are not listed; get_remote_execution_usage counts them once they finish. Finished invocations come from list_bazel_invocations."
  end

  def execute(_conn, _args, project) do
    case Query.activity(project) do
      {:ok, activity} -> {:ok, activity}
      {:error, :unavailable} -> {:error, "Remote execution activity is unavailable. Retry shortly."}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.GetRemoteExecutionUsage do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_remote_execution_usage",
    title: "Get Remote Execution Usage",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" =>
        Map.merge(
          %{
            "account_handle" => %{"type" => "string", "description" => "The account handle."},
            "project_handle" => %{"type" => "string", "description" => "The project handle."}
          },
          Map.new(Tuist.RemoteExecution.Schemas.usage_inputs(), fn {key, schema} ->
            {to_string(key), Tuist.MCP.Tool.json_schema(schema)}
          end)
        ),
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: Tuist.MCP.Tool.json_schema(Tuist.RemoteExecution.Schemas.usage())

  alias Tuist.RemoteExecution.Query

  @impl EMCP.Tool
  def description do
    "Get a project's remote execution usage over a period: executions and the time the executor ran in each VM, in total, per VM shape, per dispatch mode and per hour, day or month. Cache hits are not executions. Defaults to the last 30 days; at most #{Query.max_days()} days."
  end

  def execute(_conn, args, project) do
    case Query.usage(project, args) do
      {:ok, usage} ->
        {:ok, usage}

      {:error, :invalid_period} ->
        {:error, "Use ISO 8601 from/to timestamps for an ordered period of at most #{Query.max_days()} days."}
    end
  end
end
