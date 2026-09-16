defmodule Atlas.MCP.Tools.ListFinanceInvoices do
  @moduledoc """
  Lists extracted vendor invoices and cost breakdowns in Atlas.
  """

  use Atlas.MCP.Tool,
    name: "list_finance_invoices",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string", "enum" => ["extracted", "needs_review", "failed"]},
        "vendor" => %{"type" => "string", "description" => "Filter by vendor name."},
        "category_slug" => %{"type" => "string", "description" => "Filter by line-item finance category slug."},
        "date_from" => %{"type" => "string", "description" => "Inclusive invoice date lower bound, YYYY-MM-DD."},
        "date_to" => %{"type" => "string", "description" => "Inclusive invoice date upper bound, YYYY-MM-DD."},
        "query" => %{
          "type" => "string",
          "description" => "Search vendor, invoice number, document title, or line item."
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "invoices" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "vendor_name" => %{"type" => ["string", "null"]},
              "invoice_number" => %{"type" => ["string", "null"]},
              "invoice_date" => %{"type" => ["string", "null"]},
              "due_date" => %{"type" => ["string", "null"]},
              "period_start" => %{"type" => ["string", "null"]},
              "period_end" => %{"type" => ["string", "null"]},
              "status" => %{"type" => ["string", "null"]},
              "total_amount_value" => %{"type" => ["string", "null"]},
              "total_amount_currency" => %{"type" => ["string", "null"]},
              "tax_amount_value" => %{"type" => ["string", "null"]},
              "tax_amount_currency" => %{"type" => ["string", "null"]},
              "confidence" => %{"type" => ["string", "null"]},
              "extracted_by_agent" => %{"type" => ["string", "null"]},
              "extracted_at" => %{"type" => ["string", "null"]},
              "last_error" => %{"type" => ["string", "null"]},
              "metadata" => %{"type" => ["object", "null"]},
              "document" =>
                Atlas.MCP.Tool.nullable(%{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "string"},
                    "title" => %{"type" => ["string", "null"]},
                    "path" => %{"type" => "string"}
                  },
                  "required" => ["id", "title", "path"],
                  "additionalProperties" => false
                }),
              "transaction" =>
                Atlas.MCP.Tool.nullable(%{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "string"},
                    "external_id" => %{"type" => ["string", "null"]},
                    "provider" => %{"type" => ["string", "null"]},
                    "counterparty_name" => %{"type" => ["string", "null"]},
                    "amount_value" => %{"type" => ["string", "null"]},
                    "amount_currency" => %{"type" => ["string", "null"]}
                  },
                  "required" => [
                    "id",
                    "external_id",
                    "provider",
                    "counterparty_name",
                    "amount_value",
                    "amount_currency"
                  ],
                  "additionalProperties" => false
                }),
              "line_items" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "string"},
                    "description" => %{"type" => ["string", "null"]},
                    "cost_type" => %{"type" => ["string", "null"]},
                    "amount_value" => %{"type" => ["string", "null"]},
                    "amount_currency" => %{"type" => ["string", "null"]},
                    "quantity" => %{"type" => ["string", "null"]},
                    "unit_amount_value" => %{"type" => ["string", "null"]},
                    "unit_amount_currency" => %{"type" => ["string", "null"]},
                    "service_period_start" => %{"type" => ["string", "null"]},
                    "service_period_end" => %{"type" => ["string", "null"]},
                    "confidence" => %{"type" => ["string", "null"]},
                    "metadata" => %{"type" => ["object", "null"]},
                    "category" =>
                      Atlas.MCP.Tool.nullable(%{
                        "type" => "object",
                        "properties" => %{
                          "id" => %{"type" => "string"},
                          "name" => %{"type" => ["string", "null"]},
                          "slug" => %{"type" => ["string", "null"]}
                        },
                        "required" => ["id", "name", "slug"],
                        "additionalProperties" => false
                      })
                  },
                  "required" => [
                    "id",
                    "description",
                    "cost_type",
                    "amount_value",
                    "amount_currency",
                    "quantity",
                    "unit_amount_value",
                    "unit_amount_currency",
                    "service_period_start",
                    "service_period_end",
                    "confidence",
                    "metadata",
                    "category"
                  ],
                  "additionalProperties" => false
                }
              }
            },
            "required" => [
              "id",
              "vendor_name",
              "invoice_number",
              "invoice_date",
              "due_date",
              "period_start",
              "period_end",
              "status",
              "total_amount_value",
              "total_amount_currency",
              "tax_amount_value",
              "tax_amount_currency",
              "confidence",
              "extracted_by_agent",
              "extracted_at",
              "last_error",
              "metadata",
              "document",
              "transaction",
              "line_items"
            ],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["invoices", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance
  alias Atlas.Finance.Invoice
  alias Atlas.Finance.InvoiceLineItem
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List extracted vendor invoices with granular line-item cost breakdowns."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn) do
      invoices =
        args
        |> list_opts()
        |> Finance.list_invoices()
        |> Enum.map(&serialize_invoice/1)

      {:ok, %{invoices: invoices, count: length(invoices)}}
    end
  end

  defp list_opts(args) do
    [
      limit: Tool.page_size(args),
      status: present(args, "status"),
      vendor: present(args, "vendor"),
      category_slug: present(args, "category_slug"),
      date_from: parse_date(args["date_from"]),
      date_to: parse_date(args["date_to"]),
      query: present(args, "query")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp serialize_invoice(%Invoice{} = invoice) do
    %{
      id: invoice.id,
      vendor_name: invoice.vendor_name,
      invoice_number: invoice.invoice_number,
      invoice_date: Tool.iso8601(invoice.invoice_date),
      due_date: Tool.iso8601(invoice.due_date),
      period_start: Tool.iso8601(invoice.period_start),
      period_end: Tool.iso8601(invoice.period_end),
      status: invoice.status,
      total_amount_value: decimal_to_string(invoice.total_amount_value),
      total_amount_currency: invoice.total_amount_currency,
      tax_amount_value: decimal_to_string(invoice.tax_amount_value),
      tax_amount_currency: invoice.tax_amount_currency,
      confidence: decimal_to_string(invoice.confidence),
      extracted_by_agent: invoice.extracted_by_agent,
      extracted_at: Tool.iso8601(invoice.extracted_at),
      last_error: invoice.last_error,
      metadata: invoice.metadata,
      document: serialize_document(invoice.document),
      transaction: serialize_transaction(invoice.transaction),
      line_items: Enum.map(invoice.line_items, &serialize_line_item/1)
    }
  end

  defp serialize_line_item(%InvoiceLineItem{} = line_item) do
    %{
      id: line_item.id,
      description: line_item.description,
      cost_type: line_item.cost_type,
      amount_value: decimal_to_string(line_item.amount_value),
      amount_currency: line_item.amount_currency,
      quantity: decimal_to_string(line_item.quantity),
      unit_amount_value: decimal_to_string(line_item.unit_amount_value),
      unit_amount_currency: line_item.unit_amount_currency,
      service_period_start: Tool.iso8601(line_item.service_period_start),
      service_period_end: Tool.iso8601(line_item.service_period_end),
      confidence: decimal_to_string(line_item.confidence),
      metadata: line_item.metadata,
      category: serialize_category(line_item.category)
    }
  end

  defp serialize_document(nil), do: nil

  defp serialize_document(document) do
    %{id: document.id, title: document.title, path: "/documents/#{document.id}"}
  end

  defp serialize_transaction(nil), do: nil

  defp serialize_transaction(transaction) do
    %{
      id: transaction.id,
      external_id: transaction.external_id,
      provider: transaction.provider,
      counterparty_name: transaction.counterparty_name,
      amount_value: decimal_to_string(transaction.amount_value),
      amount_currency: transaction.amount_currency
    }
  end

  defp serialize_category(nil), do: nil

  defp serialize_category(category) do
    %{id: category.id, name: category.name, slug: category.slug}
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
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
