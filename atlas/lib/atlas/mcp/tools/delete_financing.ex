defmodule Atlas.MCP.Tools.DeleteFinancing do
  use Atlas.MCP.Tool,
    name: "delete_financing",
    schema: %{
      "type" => "object",
      "required" => ["financing_id"],
      "properties" => %{"financing_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "deleted" => %{"type" => "boolean"}
      },
      "required" => ["financing_id", "deleted"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Permanently delete a financing arrangement. Only allowed when status is active and no payments have been matched. Owned schedules and lines are cleaned up. Executive only."
  end

  def execute(conn, %{"financing_id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools"),
         %_{} = financing <- Financings.get(id) do
      case Financings.delete(financing) do
        {:ok, deleted} -> {:ok, %{financing_id: deleted.id, deleted: true}}
        {:error, changeset} -> {:error, "Could not delete financing: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Financing not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id is required."}
end
