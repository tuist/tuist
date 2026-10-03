defmodule Atlas.MCP.Tools.AttachDocumentToFinancing do
  use Atlas.MCP.Tool,
    name: "attach_document_to_financing",
    schema: %{
      "type" => "object",
      "required" => ["financing_id", "document_id", "kind"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "kind" => %{"type" => "string", "enum" => Atlas.Finance.FinancingDocument.kinds()},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "financing_id" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "kind" => %{"type" => "string"}
      },
      "required" => ["id", "financing_id", "document_id", "kind"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Attach a supplier contract, financing agreement, guarantee, or other document to a hardware financing. Executive only."
  end

  def execute(conn, %{"financing_id" => financing_id, "document_id" => document_id, "kind" => kind} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools"),
         %_{} = financing <- Financings.get(financing_id) do
      opts = if is_binary(args["notes"]), do: [notes: args["notes"]], else: []

      case Financings.attach_document(financing, document_id, kind, opts) do
        {:ok, link} ->
          {:ok, %{id: link.id, financing_id: link.financing_id, document_id: link.document_id, kind: link.kind}}

        {:error, :document_not_found} ->
          {:error, "Document not found."}

        {:error, :document_not_ready} ->
          {:error, "Document upload is not complete."}

        {:error, changeset} ->
          {:error, "Could not attach document: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Financing not found."}
      other -> other
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id, document_id, and kind are required."}
end
