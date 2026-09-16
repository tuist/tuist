defmodule Atlas.MCP.Tools.GetFinanceExpenseReconciliation do
  @moduledoc """
  Reconciles every cash expense in a date range across all synced finance accounts.
  """

  use Atlas.MCP.Tool,
    name: "get_finance_expense_reconciliation",
    schema: %{
      "type" => "object",
      "properties" => %{
        "date_from" => %{"type" => "string", "description" => "Inclusive expense date, YYYY-MM-DD."},
        "date_to" => %{"type" => "string", "description" => "Inclusive expense date, YYYY-MM-DD."},
        "currency" => %{
          "type" => "string",
          "description" => "Optional report currency. Defaults to Atlas's configured report currency."
        }
      },
      "required" => ["date_from", "date_to"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "period" => %{
          "type" => "object",
          "properties" => %{"date_from" => %{"type" => "string"}, "date_to" => %{"type" => "string"}},
          "required" => ["date_from", "date_to"],
          "additionalProperties" => false
        },
        "currency" => %{"type" => "string"},
        "total_amount_value" => %{"type" => "string"},
        "included_transaction_count" => %{"type" => "integer"},
        "matching_debit_transaction_count" => %{"type" => "integer"},
        "complete" => %{"type" => "boolean"},
        "exchange_rate" => %{
          "type" => "object",
          "properties" => %{
            "basis" => %{"type" => "string"},
            "published_on" => %{"type" => ["string", "null"]},
            "available" => %{"type" => "boolean"},
            "report_currency" => %{"type" => "string"}
          },
          "required" => ["basis", "published_on", "available", "report_currency"],
          "additionalProperties" => false
        },
        "accounts" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => ["string", "null"]},
              "provider" => %{"type" => ["string", "null"]},
              "source_key" => %{"type" => ["string", "null"]},
              "source_name" => %{"type" => ["string", "null"]},
              "currency" => %{"type" => ["string", "null"]},
              "last_successful_sync_at" => %{"type" => ["string", "null"]},
              "matching_expense_transaction_count" => %{"type" => "integer"},
              "total_amount_value" => %{"type" => "string"}
            },
            "required" => [
              "id",
              "name",
              "provider",
              "source_key",
              "source_name",
              "currency",
              "last_successful_sync_at",
              "matching_expense_transaction_count",
              "total_amount_value"
            ],
            "additionalProperties" => false
          }
        },
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
        "currencies" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "currency" => %{"type" => ["string", "null"]},
              "transaction_count" => %{"type" => "integer"},
              "total_amount_value" => %{"type" => "string"}
            },
            "required" => ["currency", "transaction_count", "total_amount_value"],
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
          "required" => ["non_expense_transaction_count", "unconverted_transaction_count", "unconverted_currencies"],
          "additionalProperties" => false
        }
      },
      "required" => [
        "period",
        "currency",
        "total_amount_value",
        "included_transaction_count",
        "matching_debit_transaction_count",
        "complete",
        "exchange_rate",
        "accounts",
        "categories",
        "currencies",
        "exclusions"
      ],
      "additionalProperties" => false
    }

  alias Atlas.Accounts.Amounts
  alias Atlas.Finance
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Reconcile every cash expense in a date range across all synced Qonto and Mercury accounts. Returns an exact server-side total, account coverage, category totals, source-currency totals, exclusions, and foreign-exchange basis. Use this for month-over-month expense questions instead of summing list_finance_transactions results."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn),
         {:ok, date_from} <- parse_date(Map.get(args, "date_from"), :from),
         {:ok, date_to} <- parse_date(Map.get(args, "date_to"), :to),
         :ok <- validate_period(date_from, date_to),
         {:ok, currency} <- parse_currency(Map.get(args, "currency")) do
      reconciliation = Finance.expense_reconciliation(date_from: date_from, date_to: date_to, currency: currency)
      {:ok, serialize(reconciliation)}
    end
  end

  defp parse_date(value, edge) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        time = if edge == :from, do: ~T[00:00:00], else: ~T[23:59:59]
        {:ok, DateTime.new!(date, time, "Etc/UTC")}

      _ ->
        {:error, "date_#{edge} must be an ISO-8601 date in YYYY-MM-DD format."}
    end
  end

  defp parse_date(_value, edge), do: {:error, "date_#{edge} must be an ISO-8601 date in YYYY-MM-DD format."}

  defp validate_period(date_from, date_to) do
    if DateTime.after?(date_from, date_to), do: {:error, "date_from must be on or before date_to."}, else: :ok
  end

  defp parse_currency(nil), do: {:ok, nil}

  defp parse_currency(value) when is_binary(value) do
    case Amounts.normalize_currency(value) do
      nil -> {:error, "currency must not be blank."}
      currency -> {:ok, currency}
    end
  end

  defp parse_currency(_value), do: {:error, "currency must be a currency code."}

  defp serialize(reconciliation) do
    %{
      period: %{
        date_from: Date.to_iso8601(reconciliation.period.date_from),
        date_to: Date.to_iso8601(reconciliation.period.date_to)
      },
      currency: reconciliation.currency,
      total_amount_value: decimal(reconciliation.total_amount_value),
      included_transaction_count: reconciliation.included_transaction_count,
      matching_debit_transaction_count: reconciliation.matching_debit_transaction_count,
      complete: reconciliation.complete?,
      exchange_rate: %{
        basis: reconciliation.exchange_rate.basis,
        published_on: date(reconciliation.exchange_rate.published_on),
        available: reconciliation.exchange_rate.available?,
        report_currency: reconciliation.exchange_rate.report_currency
      },
      accounts: Enum.map(reconciliation.accounts, &serialize_account/1),
      categories:
        Enum.map(
          reconciliation.categories,
          &%{name: &1.name, transaction_count: &1.transaction_count, total_amount_value: decimal(&1.total_amount_value)}
        ),
      currencies:
        Enum.map(
          reconciliation.currencies,
          &%{
            currency: &1.currency,
            transaction_count: &1.transaction_count,
            total_amount_value: decimal(&1.total_amount_value)
          }
        ),
      exclusions: reconciliation.exclusions
    }
  end

  defp serialize_account(account) do
    %{
      id: account.id,
      name: account.name,
      provider: account.provider,
      source_key: account.source_key,
      source_name: account.source_name,
      currency: account.currency,
      last_successful_sync_at: Tool.iso8601(account.last_successful_sync_at),
      matching_expense_transaction_count: account.matching_expense_transaction_count,
      total_amount_value: decimal(account.total_amount_value)
    }
  end

  defp decimal(value), do: Decimal.to_string(value)
  defp date(nil), do: nil
  defp date(%Date{} = value), do: Date.to_iso8601(value)
end
