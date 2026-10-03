defmodule Atlas.MCP.Tools.SetFinancingLines do
  use Atlas.MCP.Tool,
    name: "set_financing_lines",
    schema: %{
      "type" => "object",
      "required" => ["financing_id", "lines"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "lines" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["asset_id", "share_bps"],
            "properties" => %{
              "asset_id" => %{"type" => "string"},
              "share_bps" => %{"type" => "integer", "minimum" => 1, "maximum" => 10_000}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"line_count" => %{"type" => "integer"}},
      "required" => ["line_count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Atomically replace the asset-line set for a financing. Shares must sum to 10000. Executive only."
  end

  def execute(conn, %{"financing_id" => id, "lines" => lines}) when is_list(lines) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools"),
         %_{} = financing <- Financings.get(id) do
      lines =
        Enum.map(lines, fn line ->
          %{asset_id: Map.fetch!(line, "asset_id"), share_bps: Map.fetch!(line, "share_bps")}
        end)

      case Financings.set_lines(financing, lines) do
        {:ok, updated_lines} -> {:ok, %{line_count: length(updated_lines)}}
        {:error, changeset} -> {:error, "Could not set lines: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Financing not found."}
      other -> other
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id and lines are required."}
end
