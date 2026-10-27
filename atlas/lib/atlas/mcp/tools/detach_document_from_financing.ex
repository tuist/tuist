defmodule Atlas.MCP.Tools.DetachDocumentFromFinancing do
  use Atlas.MCP.Tool,
    name: "detach_document_from_financing",
    schema: %{
      "type" => "object",
      "required" => ["link_id"],
      "properties" => %{"link_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "required" => ["deleted"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Detach a document from a hardware financing without deleting the document. Executive only."
  end

  def execute(conn, %{"link_id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools") do
      case Financings.detach_document(id) do
        {:ok, _link} -> {:ok, %{deleted: true}}
        {:error, :not_found} -> {:error, "Attachment not found."}
        {:error, changeset} -> {:error, "Could not detach document: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "link_id is required."}
end
