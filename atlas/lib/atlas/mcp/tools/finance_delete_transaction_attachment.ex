defmodule Atlas.MCP.Tools.FinanceDeleteTransactionAttachment do
  @moduledoc """
  Deletes an attachment from a finance transaction.
  """

  use Atlas.MCP.Tool,
    name: "finance_delete_transaction_attachment",
    schema: %{
      "type" => "object",
      "properties" => %{
        "source_key" => %{
          "type" => "string",
          "description" => "The finance source key."
        },
        "attachment_id" => %{
          "type" => "string",
          "description" =>
            "The provider attachment ID to delete (from finance_list_transaction_attachments or finance_get_transaction)."
        }
      },
      "required" => ["source_key", "attachment_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "success" => %{"type" => "boolean"},
        "attachment_id" => %{"type" => "string"},
        "message" => %{"type" => "string"}
      },
      "required" => ["success", "attachment_id", "message"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tool

  def description do
    "Delete an attachment from a finance transaction by its attachment ID. Use this to remove incorrect or duplicate attachments."
  end

  def execute(conn, %{"source_key" => source_key, "attachment_id" => attachment_id}) do
    with :ok <- Tool.authorize_executive(conn),
         {:ok, source} <- Config.fetch_source(source_key) do
      case Qonto.delete_attachment(source, attachment_id) do
        :ok ->
          {:ok, %{success: true, attachment_id: attachment_id, message: "Attachment deleted successfully."}}

        {:error, reason} ->
          {:error, "Failed to delete attachment: #{inspect(reason)}"}
      end
    else
      {:error, :source_not_configured} ->
        {:error, "No finance source configured with key '#{source_key}'."}

      {:error, reason} ->
        {:error, "Failed to delete attachment: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args) do
    {:error, "source_key and attachment_id are required."}
  end
end
