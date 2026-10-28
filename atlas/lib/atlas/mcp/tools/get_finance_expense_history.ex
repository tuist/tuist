defmodule Atlas.MCP.Tools.GetFinanceExpenseHistory do
  @moduledoc """
  Returns month-by-month cash-expense history across all synced finance accounts.
  """

  use Atlas.MCP.Tool,
    name: "get_finance_expense_history",
    schema: %{
      "type" => "object",
      "properties" => %{
        "ending_on" => %{"type" => "string", "description" => "Final expense date, YYYY-MM-DD."},
        "months" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 12,
          "description" => "Number of calendar months to include. Defaults to 3."
        },
        "currency" => %{
          "type" => "string",
          "description" => "Optional report currency. Defaults to Atlas's configured report currency."
        }
      },
      "required" => ["ending_on"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "currency" => %{"type" => "string"},
        "months" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "date_from" => %{"type" => "string"},
              "date_to" => %{"type" => "string"},
              "partial" => %{"type" => "boolean"},
              "total_amount_value" => %{"type" => "string"},
              "included_transaction_count" => %{"type" => "integer"},
              "matching_debit_transaction_count" => %{"type" => "integer"},
              "complete" => %{"type" => "boolean"},
              "categories" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "properties" => %{
                    "name" => %{"type" => "string"},
                    "transaction_count" => %{"type" => "integer"},
                    "total_amount_value" => %{"type" => "string"}
                  },
                  "required" => ["name", "transaction_count", "total_amount_value"],
                  "additionalProperties" => false
                }
              },
              "exclusions" => %{
                "type" => "object",
                "properties" => %{
                  "non_expense_transaction_count" => %{"type" => "integer"},
                  "unconverted_transaction_count" => %{"type" => "integer"},
                  "unconverted_currencies" => %{"type" => "array", "items" => %{"type" => "string"}}
                },
                "required" => [
                  "non_expense_transaction_count",
                  "unconverted_transaction_count",
                  "unconverted_currencies"
                ],
                "additionalProperties" => false
              }
            },
            "required" => [
              "date_from",
              "date_to",
              "partial",
              "total_amount_value",
              "included_transaction_count",
              "matching_debit_transaction_count",
              "complete",
              "categories",
              "exclusions"
            ],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["currency", "months"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.Amounts
  alias Atlas.Finance
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Return exact monthly cash-expense totals, category totals, and coverage details across all synced finance accounts. Use it to explain how costs have evolved over recent calendar months."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:read", "Finance tools"),
         {:ok, ending_on} <- parse_date(Map.get(args, "ending_on")),
         {:ok, months} <- parse_months(Map.get(args, "months")),
         {:ok, currency} <- parse_currency(Map.get(args, "currency")) do
      history = Finance.expense_history(ending_on: ending_on, months: months, currency: currency)
      {:ok, serialize(history)}
    end
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "ending_on must be an ISO-8601 date in YYYY-MM-DD format."}
    end
  end

  defp parse_date(_value), do: {:error, "ending_on must be an ISO-8601 date in YYYY-MM-DD format."}

  defp parse_months(nil), do: {:ok, 3}
  defp parse_months(value) when is_integer(value) and value in 1..12, do: {:ok, value}
  defp parse_months(_value), do: {:error, "months must be an integer between 1 and 12."}

  defp parse_currency(nil), do: {:ok, nil}

  defp parse_currency(value) when is_binary(value) do
    case Amounts.normalize_currency(value) do
      nil -> {:error, "currency must not be blank."}
      currency -> {:ok, currency}
    end
  end

  defp parse_currency(_value), do: {:error, "currency must be a currency code."}

  defp serialize(history) do
    %{
      currency: history.currency,
      months: Enum.map(history.months, &serialize_month/1)
    }
  end

  defp serialize_month(month) do
    %{
      date_from: Date.to_iso8601(month.period.date_from),
      date_to: Date.to_iso8601(month.period.date_to),
      partial: month.period.partial?,
      total_amount_value: Decimal.to_string(month.total_amount_value),
      included_transaction_count: month.included_transaction_count,
      matching_debit_transaction_count: month.matching_debit_transaction_count,
      complete: month.complete?,
      categories:
        Enum.map(month.categories, fn category ->
          %{
            name: category.name,
            transaction_count: category.transaction_count,
            total_amount_value: Decimal.to_string(category.total_amount_value)
          }
        end),
      exclusions: month.exclusions
    }
  end
end
