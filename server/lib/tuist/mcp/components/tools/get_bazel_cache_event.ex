defmodule Tuist.MCP.Components.Tools.GetBazelCacheEvent do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "get_bazel_cache_event",
    title: "Get Bazel Cache Event",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "cache_event_id" => %{"type" => "string", "description" => "The Bazel cache event identifier."}
      },
      "required" => ["account_handle", "project_handle", "cache_event_id"]
    },
    output_schema: Tuist.MCP.Components.Tools.BazelCacheEvent.schema()

  alias Tuist.MCP.Components.Tools.BazelCacheEvent
  alias Tuist.ReapiCache

  @impl EMCP.Tool
  def description, do: "Get one raw Bazel remote-cache observation."

  def execute(_conn, %{"cache_event_id" => cache_event_id}, project) do
    case ReapiCache.get_cache_event(project.id, cache_event_id) do
      {:ok, event} -> {:ok, BazelCacheEvent.json(event)}
      {:error, :not_found} -> {:error, "Bazel cache event not found: #{cache_event_id}"}
    end
  end
end
