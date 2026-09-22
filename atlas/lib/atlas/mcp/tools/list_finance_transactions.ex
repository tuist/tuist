defmodule Atlas.MCP.Tools.ListFinanceTransactions do
  @moduledoc """
  Lists normalized finance transactions in Atlas.
  """

  use Atlas.MCP.Tool,
    name: "list_finance_transactions",
    schema: %{
      "type" => "object",
      "properties" => %{
        "provider" => %{
          "type" => "string",
          "enum" => ["qonto", "mercury"],
          "description" => "Filter transactions by provider."
        },
        "atlas_account_key" => %{
          "type" => "string",
          "description" => "Filter transactions by the linked Atlas company account key."
        },
        "source_key" => %{
          "type" => "string",
          "description" => "Filter transactions by configured finance source key."
        },
        "account_id" => %{
          "type" => "string",
          "description" => "Filter transactions to a specific normalized finance account id."
        },
        "currency" => %{
          "type" => "string",
          "description" => "Filter transactions by amount currency, for example EUR or USD."
        },
        "direction" => %{
          "type" => "string",
          "enum" => ["credit", "debit"],
          "description" => "Filter transactions by money in or money out."
        },
        "status" => %{
          "type" => "string",
          "description" => "Filter transactions by provider-normalized status."
        },
        "kind" => %{
          "type" => "string",
          "description" => "Filter transactions by provider-normalized transaction kind."
        },
        "category_id" => %{
          "type" => "string",
          "description" => "Filter transactions by broad finance category id."
        },
        "category_slug" => %{
          "type" => "string",
          "description" => "Filter transactions by broad finance category slug."
        },
        "uncategorized" => %{
          "type" => "boolean",
          "description" => "When true, return only transactions without a category."
        },
        "date_from" => %{
          "type" => "string",
          "description" => "Inclusive lower bound for the transaction date. Accepts ISO-8601 date or datetime."
        },
        "date_to" => %{
          "type" => "string",
          "description" => "Inclusive upper bound for the transaction date. Accepts ISO-8601 date or datetime."
        },
        "query" => %{
          "type" => "string",
          "description" =>
            "Free-text search across counterparty, description, reference, account name, and source name."
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "transactions" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "provider" => %{"type" => ["string", "null"]},
              "external_id" => %{"type" => ["string", "null"]},
              "occurred_at" => %{"type" => ["string", "null"]},
              "booked_at" => %{"type" => ["string", "null"]},
              "settled_at" => %{"type" => ["string", "null"]},
              "provider_updated_at" => %{"type" => ["string", "null"]},
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
              "fee_value" => %{"type" => ["string", "null"]},
              "fee_currency" => %{"type" => ["string", "null"]},
              "running_balance_value" => %{"type" => ["string", "null"]},
              "running_balance_currency" => %{"type" => ["string", "null"]},
              "affects_cash_balance" => %{"type" => ["boolean", "null"]},
              "affects_runway" => %{"type" => ["boolean", "null"]},
              "category" =>
                Atlas.MCP.Tool.nullable(%{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "string"},
                    "name" => %{"type" => ["string", "null"]},
                    "slug" => %{"type" => ["string", "null"]},
                    "description" => %{"type" => ["string", "null"]},
                    "direction" => %{"type" => ["string", "null"]}
                  },
                  "required" => ["id", "name", "slug", "description", "direction"],
                  "additionalProperties" => false
                }),
              "categorized_at" => %{"type" => ["string", "null"]},
              "categorization_confidence" => %{"type" => ["string", "null"]},
              "categorization_reason" => %{"type" => ["string", "null"]},
              "categorized_by_agent" => %{"type" => ["string", "null"]},
              "metadata" => %{"type" => ["object", "null"]},
              "account" => %{
                "type" => "object",
                "properties" => %{
                  "id" => %{"type" => "string"},
                  "atlas_account" =>
                    Atlas.MCP.Tool.nullable(%{
                      "type" => "object",
                      "properties" => %{
                        "id" => %{"type" => "string"},
                        "account_key" => %{"type" => "string"},
                        "name" => %{"type" => ["string", "null"]}
                      },
                      "required" => ["id", "account_key", "name"],
                      "additionalProperties" => false
                    }),
                  "name" => %{"type" => ["string", "null"]},
                  "currency" => %{"type" => ["string", "null"]},
                  "provider" => %{"type" => ["string", "null"]},
                  "source_key" => %{"type" => ["string", "null"]},
                  "source_name" => %{"type" => ["string", "null"]}
                },
                "required" => ["id", "atlas_account", "name", "currency", "provider", "source_key", "source_name"],
                "additionalProperties" => false
              }
            },
            "required" => [
              "id",
              "provider",
              "external_id",
              "occurred_at",
              "booked_at",
              "settled_at",
              "provider_updated_at",
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
              "fee_value",
              "fee_currency",
              "running_balance_value",
              "running_balance_currency",
              "affects_cash_balance",
              "affects_runway",
              "category",
              "categorized_at",
              "categorization_confidence",
              "categorization_reason",
              "categorized_by_agent",
              "metadata",
              "account"
            ],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["transactions", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance
  alias Atlas.Finance.Transaction
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List normalized finance transactions in Atlas with filters for source, account, dates, direction, status, kind, currency, and search."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:read", "Finance tools") do
      transactions =
        args
        |> list_opts()
        |> Finance.list_transactions()
        |> Enum.map(&serialize_transaction/1)

      {:ok, %{transactions: transactions, count: length(transactions)}}
    end
  end

  defp list_opts(args) do
    [
      limit: Tool.page_size(args),
      provider: present(args, "provider"),
      atlas_account_key: present(args, "atlas_account_key"),
      source_key: present(args, "source_key"),
      account_id: present(args, "account_id"),
      currency: present(args, "currency"),
      direction: present(args, "direction"),
      status: present(args, "status"),
      kind: present(args, "kind"),
      category_id: present(args, "category_id"),
      category_slug: present(args, "category_slug"),
      uncategorized: Map.get(args, "uncategorized") == true,
      date_from: parse_date_from(Map.get(args, "date_from")),
      date_to: parse_date_to(Map.get(args, "date_to")),
      query: present(args, "query")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp serialize_transaction(%Transaction{} = transaction) do
    %{
      id: transaction.id,
      provider: transaction.provider,
      external_id: transaction.external_id,
      occurred_at: Tool.iso8601(Transaction.occurred_at(transaction)),
      booked_at: Tool.iso8601(transaction.booked_at),
      settled_at: Tool.iso8601(transaction.settled_at),
      provider_updated_at: Tool.iso8601(transaction.provider_updated_at),
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
      fee_value: decimal_to_string(transaction.fee_value),
      fee_currency: transaction.fee_currency,
      running_balance_value: decimal_to_string(transaction.running_balance_value),
      running_balance_currency: transaction.running_balance_currency,
      affects_cash_balance: transaction.affects_cash_balance,
      affects_runway: transaction.affects_runway,
      category: serialize_category(transaction.category),
      categorized_at: Tool.iso8601(transaction.categorized_at),
      categorization_confidence: decimal_to_string(transaction.categorization_confidence),
      categorization_reason: transaction.categorization_reason,
      categorized_by_agent: transaction.categorized_by_agent,
      metadata: transaction.metadata,
      account: %{
        id: transaction.account.id,
        atlas_account: serialize_atlas_account(transaction.account.source.atlas_account),
        name: transaction.account.name,
        currency: transaction.account.currency,
        provider: transaction.account.provider,
        source_key: transaction.account.source.config_key,
        source_name: transaction.account.source.name
      }
    }
  end

  defp serialize_atlas_account(nil), do: nil

  defp serialize_atlas_account(atlas_account) do
    %{
      id: atlas_account.id,
      account_key: atlas_account.account_key,
      name: atlas_account.name
    }
  end

  defp serialize_category(nil), do: nil

  defp serialize_category(category) do
    %{
      id: category.id,
      name: category.name,
      slug: category.slug,
      description: category.description,
      direction: category.direction
    }
  end

  defp parse_date_from(nil), do: nil
  defp parse_date_from(value), do: parse_date(value, ~T[00:00:00])

  defp parse_date_to(nil), do: nil
  defp parse_date_to(value), do: parse_date(value, ~T[23:59:59])

  defp parse_date(value, fallback_time) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        DateTime.new!(date, fallback_time, "Etc/UTC")

      {:error, _reason} ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
          {:error, _reason} -> nil
        end
    end
  end

  defp present(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(value), do: Decimal.to_string(value)
end
