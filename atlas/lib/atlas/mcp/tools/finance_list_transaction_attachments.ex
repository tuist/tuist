defmodule Atlas.MCP.Tools.FinanceListTransactionAttachments do
  @moduledoc """
  Lists attachments for a transaction from the configured finance provider.
  """

  use Atlas.MCP.Tool,
    name: "finance_list_transaction_attachments",
    schema: %{
      "type" => "object",
      "properties" => %{
        "source_key" => %{
          "type" => "string",
          "description" => "The finance source key (e.g. the configured Qonto source key)."
        },
        "transaction_external_id" => %{
          "type" => "string",
          "description" => "The provider transaction external ID (from finance_get_transaction)."
        }
      },
      "required" => ["source_key", "transaction_external_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "attachments" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "file_name" => %{"type" => ["string", "null"]},
              "file_content_type" => %{"type" => ["string", "null"]},
              "file_size" => %{"type" => ["integer", "null"]},
              "url" => %{"type" => ["string", "null"]},
              "probative" => %{"type" => "boolean"}
            },
            "required" => ["id", "file_name", "file_content_type", "file_size", "url", "probative"],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["attachments", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tool

  def description do
    "List all attachments for a specific finance transaction, including probative attachments. Use this to inspect which receipts or documents are already linked."
  end

  def execute(conn, %{"source_key" => source_key, "transaction_external_id" => transaction_external_id}) do
    with :ok <- Tool.authorize_scope(conn, "finance:read", "Finance tools"),
         {:ok, source} <- Config.fetch_source(source_key) do
      case Qonto.list_transaction_attachments(source, transaction_external_id) do
        {:ok, attachments} ->
          serialized = Enum.map(attachments, &serialize_attachment/1)
          {:ok, %{attachments: serialized, count: length(serialized)}}

        {:error, reason} ->
          {:error, "Failed to list attachments: #{inspect(reason)}"}
      end
    else
      {:error, :source_not_configured} ->
        {:error, "No finance source configured with key '#{source_key}'."}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}
    end
  end

  def execute(_conn, _args) do
    {:error, "source_key and transaction_external_id are required."}
  end

  defp serialize_attachment(attachment) do
    %{
      id: attachment["id"],
      file_name: attachment["file_name"],
      file_content_type: attachment["file_content_type"],
      file_size: parse_integer(attachment["file_size"]),
      url: attachment["url"],
      probative: is_map(attachment["probative_attachment"])
    }
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(value) when is_binary(value), do: String.to_integer(value)
  defp parse_integer(_value), do: nil
end
