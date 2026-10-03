defmodule Atlas.MCP.Tools.ListInvoices do
  @moduledoc """
  Lists invoices across all accounts, defaulting to reconciled Stripe invoices.
  """

  use Atlas.MCP.Tool,
    name: "list_invoices",
    schema: %{
      "type" => "object",
      "properties" => %{
        "source" => %{
          "type" => "string",
          "enum" => ["stripe", "all"],
          "description" => ~s{Invoice source to return. Defaults to "stripe".}
        },
        "status" => %{
          "type" => "string",
          "description" => ~s{Filter to a specific invoice status, for example "open", "draft", or "paid".}
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "source" => %{"type" => "string"},
        "invoices" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "external_id" => %{"type" => ["string", "null"]},
              "source" => %{"type" => ["string", "null"]},
              "number" => %{"type" => ["string", "null"]},
              "due_date" => %{"type" => ["string", "null"]},
              "amount_value" => %{"type" => ["string", "null"]},
              "amount_currency" => %{"type" => ["string", "null"]},
              "status" => %{"type" => ["string", "null"]},
              "stripe_url" => %{"type" => ["string", "null"]},
              "account" =>
                Atlas.MCP.Tool.nullable(%{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "string"},
                    "account_key" => %{"type" => "string"},
                    "name" => %{"type" => ["string", "null"]},
                    "stripe_customer_id" => %{"type" => ["string", "null"]}
                  },
                  "required" => ["id", "account_key", "name", "stripe_customer_id"],
                  "additionalProperties" => false
                }),
              "inserted_at" => %{"type" => ["string", "null"]},
              "updated_at" => %{"type" => ["string", "null"]}
            },
            "required" => [
              "id",
              "external_id",
              "source",
              "number",
              "due_date",
              "amount_value",
              "amount_currency",
              "status",
              "stripe_url",
              "account",
              "inserted_at",
              "updated_at"
            ],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["source", "invoices", "count"],
      "additionalProperties" => false
    }

  import Ecto.Query

  alias Atlas.Accounts.Invoice
  alias Atlas.MCP.Tool
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "List invoices across all accounts, defaulting to reconciled Stripe invoices."

  def execute(_conn, args) do
    limit = Tool.page_size(args)
    source = source_filter(args)

    invoices =
      Invoice
      |> maybe_filter_source(source)
      |> maybe_filter_status(args)
      |> order_by([invoice], desc_nulls_first: invoice.due_date, desc: invoice.inserted_at)
      |> limit(^limit)
      |> preload(:account)
      |> Repo.all()
      |> Enum.map(&serialize/1)

    {:ok, %{source: source, invoices: invoices, count: length(invoices)}}
  end

  defp source_filter(%{"source" => "all"}), do: "all"
  defp source_filter(_args), do: "stripe"

  defp maybe_filter_source(query, "all"), do: query
  defp maybe_filter_source(query, source), do: where(query, [invoice], invoice.source == ^source)

  defp maybe_filter_status(query, %{"status" => status}) when is_binary(status) and status != "" do
    where(query, [invoice], invoice.status == ^status)
  end

  defp maybe_filter_status(query, _args), do: query

  defp serialize(invoice) do
    %{
      id: invoice.id,
      external_id: invoice.external_id,
      source: invoice.source,
      number: invoice.number,
      due_date: Tool.iso8601(invoice.due_date),
      amount_value: invoice.amount_value && Decimal.to_string(invoice.amount_value),
      amount_currency: invoice.amount_currency,
      status: invoice.status,
      stripe_url: invoice.stripe_url,
      account: serialize_account(invoice.account),
      inserted_at: Tool.iso8601(invoice.inserted_at),
      updated_at: Tool.iso8601(invoice.updated_at)
    }
  end

  defp serialize_account(nil), do: nil

  defp serialize_account(account) do
    %{
      id: account.id,
      account_key: account.account_key,
      name: account.name,
      stripe_customer_id: account.stripe_customer_id
    }
  end
end
