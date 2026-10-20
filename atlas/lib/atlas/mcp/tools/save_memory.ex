defmodule Atlas.MCP.Tools.SaveMemory do
  @moduledoc """
  Save a durable memory in the Atlas workspace memory store so future
  conversations can recall it.

  Mirrors the Slack agent's `memory_save` Condukt tool over MCP. See
  `Atlas.Memory` for the typed-memory-graph design (inspired by
  [spacebot.sh](https://spacebot.sh/)).
  """

  use Atlas.MCP.Tool,
    name: "save_memory",
    schema: %{
      "type" => "object",
      "required" => ["kind", "body"],
      "properties" => %{
        "kind" => %{
          "type" => "string",
          "enum" => ["fact", "preference", "decision", "identity", "event", "observation", "goal", "todo"],
          "description" =>
            "One of: fact (objective info), preference, decision (with reasoning), identity (durable persona), event, observation, goal, todo."
        },
        "body" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 4_000,
          "description" => "A single self-contained sentence or short paragraph."
        },
        "importance" => %{
          "type" => "number",
          "minimum" => 0.0,
          "maximum" => 1.0,
          "description" => "Optional. Omit to use the default for the kind."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["saved", "memory"],
      "properties" => %{
        "saved" => %{"type" => "boolean"},
        "memory" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["id", "kind", "importance"],
          "properties" => %{
            "id" => %{"type" => "string"},
            "kind" => %{"type" => "string"},
            "importance" => %{"type" => "number"}
          }
        }
      }
    }

  alias Atlas.MCP.Tool
  alias Atlas.Memory
  alias Atlas.Memory.Node, as: MemoryNode
  alias Atlas.Memory.Workers.RefreshBulletin

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, %{"kind" => kind_str, "body" => body} = args) when is_binary(kind_str) and is_binary(body) do
    with {:ok, kind} <- parse_kind(kind_str),
         {:ok, body} <- parse_body(body),
         {:ok, importance} <- parse_importance(Map.get(args, "importance")) do
      attrs =
        %{kind: kind, body: body, scope: :global}
        |> maybe_put(:importance, importance)

      case Memory.create_node(attrs) do
        {:ok, node} ->
          RefreshBulletin.schedule_debounced(:global)

          {:ok,
           %{
             saved: true,
             memory: %{
               id: node.id,
               kind: Atom.to_string(node.kind),
               importance: node.importance
             }
           }}

        {:error, changeset} ->
          {:error, Tool.format_changeset_errors(changeset)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "kind and body are required."}

  defp parse_kind(value) do
    case Enum.find(MemoryNode.kinds(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, "kind must be one of #{Enum.map_join(MemoryNode.kinds(), ", ", &Atom.to_string/1)}."}
      kind -> {:ok, kind}
    end
  end

  defp parse_body(value) do
    case String.trim(value) do
      "" -> {:error, "body is required."}
      trimmed -> {:ok, trimmed}
    end
  end

  defp parse_importance(nil), do: {:ok, nil}

  defp parse_importance(value) when is_number(value) and value >= 0.0 and value <= 1.0, do: {:ok, value * 1.0}

  defp parse_importance(_), do: {:error, "importance must be a number between 0 and 1."}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
