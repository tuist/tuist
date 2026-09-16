defmodule Atlas.MCP.Tools.FinanceGetTransaction do
  @moduledoc """
  Gets a single provider transaction by its normalized Atlas transaction ID,
  including attachment details fetched live from the provider.
  """

  use Atlas.MCP.Tool,
    name: "finance_get_transaction",
    schema: %{
      "type" => "object",
      "properties" => %{
        "transaction_id" => %{
          "type" => "string",
          "description" => "The normalized Atlas transaction ID (from list_finance_transactions)."
        }
      },
      "required" => ["transaction_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "external_id" => %{"type" => ["string", "null"]},
        "provider" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "direction" => %{"type" => ["string", "null"]},
        "kind" => %{"type" => ["string", "null"]},
        "counterparty_name" => %{"type" => ["string", "null"]},
        "description" => %{"type" => ["string", "null"]},
        "reference" => %{"type" => ["string", "null"]},
        "amount_value" => %{"type" => ["string", "null"]},
        "amount_currency" => %{"type" => ["string", "null"]},
        "local_amount_value" => %{"type" => ["string", "null"]},
        "local_amount_currency" => %{"type" => ["string", "null"]},
        "occurred_at" => %{"type" => ["string", "null"]},
        "booked_at" => %{"type" => ["string", "null"]},
        "settled_at" => %{"type" => ["string", "null"]},
        "account_id" => %{"type" => ["string", "null"]},
        "account_name" => %{"type" => ["string", "null"]},
        "source_key" => %{"type" => ["string", "null"]},
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
        }
      },
      "required" => [
        "id",
        "external_id",
        "provider",
        "status",
        "direction",
        "kind",
        "counterparty_name",
        "description",
        "reference",
        "amount_value",
        "amount_currency",
        "local_amount_value",
        "local_amount_currency",
        "occurred_at",
        "booked_at",
        "settled_at",
        "account_id",
        "account_name",
        "source_key",
        "attachments"
      ],
      "additionalProperties" => false
    }

  alias Atlas.Finance
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.Finance.Transaction
  alias Atlas.MCP.Tool

  def description do
    "Get a single finance transaction by its Atlas transaction ID with live attachment details fetched from the provider. Use this to inspect a transaction and see which attachments are already attached."
  end

  def execute(conn, %{"transaction_id" => transaction_id}) do
    with :ok <- Tool.authorize_executive(conn) do
      transactions = Finance.list_transactions(limit: 1, id: transaction_id)

      case transactions do
        [transaction] ->
          source_key = transaction.account.source.config_key
          attachments = fetch_live_attachments(source_key, transaction.external_id)
          {:ok, serialize_transaction(transaction, attachments)}

        [] ->
          {:error, "No transaction found with id '#{transaction_id}'."}
      end
    end
  end

  def execute(_conn, _args) do
    {:error, "transaction_id is required."}
  end

  defp fetch_live_attachments(_source_key, nil), do: []

  defp fetch_live_attachments(source_key, external_id) when is_binary(external_id) do
    case Config.fetch_source(source_key) do
      {:ok, source} ->
        case Qonto.list_transaction_attachments(source, external_id) do
          {:ok, attachments} -> Enum.map(attachments, &serialize_attachment/1)
          {:error, _reason} -> []
        end

      {:error, _reason} ->
        []
    end
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

  defp serialize_transaction(transaction, attachments) do
    %{
      id: transaction.id,
      external_id: transaction.external_id,
      provider: transaction.provider,
      status: transaction.status,
      direction: transaction.direction,
      kind: transaction.kind,
      counterparty_name: transaction.counterparty_name,
      description: transaction.description,
      reference: transaction.reference,
      amount_value: decimal_to_string(transaction.amount_value),
      amount_currency: transaction.amount_currency,
      local_amount_value: decimal_to_string(transaction.local_amount_value),
      local_amount_currency: transaction.local_amount_currency,
      occurred_at: Tool.iso8601(Transaction.occurred_at(transaction)),
      booked_at: Tool.iso8601(transaction.booked_at),
      settled_at: Tool.iso8601(transaction.settled_at),
      account_id: transaction.account.id,
      account_name: transaction.account.name,
      source_key: transaction.account.source.config_key,
      attachments: attachments
    }
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(value) when is_binary(value), do: String.to_integer(value)
  defp parse_integer(_value), do: nil

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(value), do: Decimal.to_string(value)
end
