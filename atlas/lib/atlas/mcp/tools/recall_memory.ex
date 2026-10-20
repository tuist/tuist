defmodule Atlas.MCP.Tools.RecallMemory do
  @moduledoc """
  Recall memories from the Atlas workspace memory store that match a query.

  Mirrors the Slack agent's `memory_recall` Condukt tool over MCP. See
  `Atlas.Memory` for the hybrid-search and supersession design (inspired
  by [spacebot.sh](https://spacebot.sh/)).
  """

  use Atlas.MCP.Tool,
    name: "recall_memory",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Free-text query, e.g. \"Acme renewal\"."
        },
        "kind" => %{
          "type" => "string",
          "enum" => ["fact", "preference", "decision", "identity", "event", "observation", "goal", "todo"],
          "description" => "Optional. Restrict to a single kind."
        },
        "max_results" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 20,
          "description" => "Optional. Defaults to 6."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["memories", "memory_count"],
      "properties" => %{
        "memories" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["id", "kind", "body", "importance", "access_count", "inserted_at", "last_accessed_at"],
            "properties" => %{
              "id" => %{"type" => "string"},
              "kind" => %{"type" => "string"},
              "body" => %{"type" => "string"},
              "importance" => %{"type" => "number"},
              "access_count" => %{"type" => "integer"},
              "inserted_at" => %{"type" => ["string", "null"]},
              "last_accessed_at" => %{"type" => ["string", "null"]}
            }
          }
        },
        "memory_count" => %{"type" => "integer"}
      }
    }

  alias Atlas.MCP.Tool
  alias Atlas.Memory
  alias Atlas.Memory.Node, as: MemoryNode

  @recall_default 6
  @recall_max 20

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, %{"query" => query} = args) when is_binary(query) do
    with {:ok, query} <- parse_query(query),
         {:ok, kind} <- parse_optional_kind(Map.get(args, "kind")) do
      limit =
        args
        |> Map.get("max_results", @recall_default)
        |> clamp(@recall_max)

      opts =
        [scope: :global, limit: limit]
        |> maybe_put(:kind, kind)

      matches = Memory.search_nodes(query, opts)

      {:ok,
       %{
         memories: Enum.map(matches, &serialize/1),
         memory_count: length(matches)
       }}
    end
  end

  def execute(_conn, _args), do: {:error, "query is required."}

  defp serialize(%MemoryNode{} = node) do
    %{
      id: node.id,
      kind: Atom.to_string(node.kind),
      body: node.body,
      importance: node.importance,
      access_count: node.access_count,
      inserted_at: Tool.iso8601(node.inserted_at),
      last_accessed_at: Tool.iso8601(node.last_accessed_at)
    }
  end

  defp parse_query(value) do
    case String.trim(value) do
      "" -> {:error, "query is required."}
      trimmed -> {:ok, trimmed}
    end
  end

  defp parse_optional_kind(nil), do: {:ok, nil}
  defp parse_optional_kind(""), do: {:ok, nil}

  defp parse_optional_kind(value) do
    case Enum.find(MemoryNode.kinds(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, "kind must be one of #{Enum.map_join(MemoryNode.kinds(), ", ", &Atom.to_string/1)}."}
      kind -> {:ok, kind}
    end
  end

  defp clamp(value, ceiling) when is_integer(value), do: value |> Kernel.max(1) |> Kernel.min(ceiling)

  defp clamp(_, ceiling), do: Kernel.min(@recall_default, ceiling)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
