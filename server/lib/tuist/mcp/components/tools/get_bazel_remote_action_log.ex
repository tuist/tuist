defmodule Tuist.MCP.Components.Tools.GetBazelRemoteActionLog do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "get_bazel_remote_action_log",
    title: "Get Bazel Remote Action Log",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema:
      Tuist.MCP.Components.Tools.BazelRemoteAction.input(
        %{
          "action_id" => %{"type" => "string", "description" => "The `id` from list_bazel_remote_actions."},
          "stream" => %{"type" => "string", "enum" => ["stdout", "stderr"]},
          "offset" => %{
            "type" => "integer",
            "minimum" => 0,
            "description" => "Byte offset in the stream to read from. Defaults to the stream's last `limit` bytes."
          },
          "limit" => %{
            "type" => "integer",
            "minimum" => 1,
            "maximum" => 65_536,
            "description" => "Bytes to read; at most 65536."
          }
        },
        ["action_id", "stream"]
      ),
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "stream" => %{"type" => "string"},
        "size_bytes" => %{"type" => "integer", "description" => "The stream's size when the action ran."},
        "offset" => %{"type" => "integer", "description" => "Where `text` starts in the stream."},
        "text" => %{"type" => "string", "description" => "Empty when the range was not recorded."},
        "recorded" => %{
          "type" => "array",
          "description" => "The stream's recorded byte ranges.",
          "items" => %{
            "type" => "object",
            "properties" => %{"offset" => %{"type" => "integer"}, "length" => %{"type" => "integer"}},
            "required" => ["offset", "length"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["stream", "size_bytes", "offset", "text", "recorded"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.RemoteExecution.Actions

  @impl EMCP.Tool
  def description do
    "Read up to 64 KiB of a remote action's stdout or stderr, by byte offset. Tuist records the first 16 KiB of each stream and copies longer ones whole, or their last 16 MiB when they are longer (kept like other run artifacts); `recorded` lists the byte ranges available. Without `offset`, returns the end of the stream, where failures usually are."
  end

  def execute(_conn, %{"invocation_id" => invocation_id, "action_id" => action_id, "stream" => stream} = args, project)
      when stream in ["stdout", "stderr"] do
    with {:ok, invocation} <- Bazel.get_invocation(project.id, invocation_id, include_cache_summary: false),
         {:ok, action} <- Actions.get(project.id, invocation.invocation_id, action_id) do
      stored = Actions.stored_logs(project.account, project, action)
      {:ok, Actions.log_range(action, stream, stored[stream], args["offset"], args["limit"])}
    else
      {:error, :not_found} -> {:error, "Remote action not found: #{action_id}"}
    end
  end
end
