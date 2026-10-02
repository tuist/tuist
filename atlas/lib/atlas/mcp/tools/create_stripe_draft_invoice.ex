defmodule Atlas.MCP.Tools.CreateStripeDraftInvoice do
  @moduledoc """
  Creates Stripe draft invoices from signed order forms.
  """

  use Atlas.MCP.Tool,
    name: "create_stripe_draft_invoice",
    schema: %{
      "type" => "object",
      "properties" =>
        Atlas.MCP.AccountLookup.identifier_schema_properties()
        |> Map.put("line_items", %{
          "type" => "array",
          "description" =>
            "Optional caller-supplied line items. When provided, Atlas uses these instead of auto-extracting from the signed order form. Use this when the order form lives on pages the extractor does not scan or when the extracted amount is wrong.",
          "items" => Atlas.MCP.LineItems.schema_item()
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "account_key" => %{"type" => "string"},
            "name" => %{"type" => ["string", "null"]},
            "stripe_customer_id" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "account_key", "name", "stripe_customer_id"],
          "additionalProperties" => false
        },
        "source_document" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "title" => %{"type" => ["string", "null"]},
            "document_date" => %{"type" => ["string", "null"]},
            "url" => %{"type" => "string"}
          },
          "required" => ["id", "title", "document_date", "url"],
          "additionalProperties" => false
        },
        "draft_invoice" => Atlas.MCP.Serializers.Accounts.invoice_schema(),
        "stripe_invoice" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "status" => %{"type" => ["string", "null"]},
            "dashboard_url" => %{"type" => ["string", "null"]},
            "hosted_url" => %{"type" => ["string", "null"]},
            "pdf_url" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "status", "dashboard_url", "hosted_url", "pdf_url"],
          "additionalProperties" => false
        },
        "line_items" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "description" => %{"type" => ["string", "null"]},
              "amount_value" => %{"type" => "string"},
              "amount_currency" => %{"type" => ["string", "null"]},
              "amount_cents" => %{"type" => ["integer", "null"]},
              "quantity" => %{"type" => ["integer", "null"]},
              "period_start" => %{"type" => ["string", "null"]},
              "period_end" => %{"type" => ["string", "null"]},
              # Read straight out of Stripe line item metadata, whose values are strings.
              "term_duration_days" => %{"type" => ["string", "null"]}
            },
            "required" => [
              "description",
              "amount_value",
              "amount_currency",
              "amount_cents",
              "quantity",
              "period_start",
              "period_end",
              "term_duration_days"
            ],
            "additionalProperties" => false
          }
        },
        "days_until_due" => %{"type" => ["integer", "null"]},
        "stripe_customer" => %{
          "type" => "object",
          "properties" => %{
            "status" => %{"type" => "string"},
            "id" => %{"type" => "string"},
            "name" => %{"type" => ["string", "null"]},
            "email" => %{"type" => ["string", "null"]},
            "dashboard_url" => %{"type" => ["string", "null"]}
          },
          "required" => ["status"],
          "additionalProperties" => false
        }
      },
      "required" => [
        "account",
        "source_document",
        "draft_invoice",
        "stripe_invoice",
        "line_items",
        "days_until_due",
        "stripe_customer"
      ],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.Accounts.Invoice
  alias Atlas.Documents.Document
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.LineItems
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Stripe

  @impl EMCP.Tool
  def description,
    do:
      "Create a Stripe draft invoice for an account using the most recent signed order form stored in Atlas. The invoice remains a draft and is not finalized or sent. Accepts an optional `line_items` override for cases where Atlas cannot auto-extract amounts from the order form."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools"),
         {:ok, account} <- AccountLookup.resolve(args) do
      account
      |> Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(build_opts(args))
      |> case do
        {:ok, result} -> {:ok, serialize_result(result)}
        {:error, reason} -> {:error, error_message(reason, account)}
      end
    end
  end

  defp build_opts(args) do
    case args["line_items"] do
      items when is_list(items) and items != [] -> [line_items: LineItems.normalize(items)]
      _other -> []
    end
  end

  defp serialize_result(%{
         account: account,
         source_document: %Document{} = document,
         draft_invoice: %Invoice{} = invoice,
         stripe_invoice: %Stripe.Invoice{} = stripe_invoice,
         line_items: line_items,
         days_until_due: days_until_due,
         stripe_customer_status: customer_status,
         stripe_customer: customer
       }) do
    %{
      account: %{
        id: account.id,
        account_key: account.account_key,
        name: account.name,
        stripe_customer_id: account.stripe_customer_id
      },
      source_document: %{
        id: document.id,
        title: document.title,
        document_date: Tool.iso8601(document.document_date),
        url: Tool.document_url(document)
      },
      draft_invoice: AccountSerializer.invoice(invoice),
      stripe_invoice: %{
        id: stripe_invoice.id,
        status: stripe_invoice.status,
        dashboard_url: stripe_invoice.dashboard_url,
        hosted_url: stripe_invoice.hosted_url,
        pdf_url: stripe_invoice.pdf_url
      },
      line_items: Enum.map(line_items, &serialize_line_item/1),
      days_until_due: days_until_due,
      stripe_customer: serialize_customer(customer, customer_status)
    }
  end

  defp serialize_customer(nil, status), do: %{status: to_string(status)}

  defp serialize_customer(%Stripe.Customer{} = customer, status) do
    %{
      status: to_string(status),
      id: customer.id,
      name: customer.name,
      email: customer.email,
      dashboard_url: customer.dashboard_url
    }
  end

  defp serialize_line_item(line_item) do
    %{
      description: line_item.description,
      amount_value: Decimal.to_string(line_item.amount_value),
      amount_currency: line_item.currency,
      amount_cents: line_item.amount_cents,
      quantity: line_item[:quantity],
      period_start: Tool.iso8601(line_item.period_start),
      period_end: Tool.iso8601(line_item.period_end),
      term_duration_days: line_item[:metadata] && line_item.metadata["term_duration_days"]
    }
  end

  defp error_message(:missing_stripe_customer_id, account) do
    "#{account.name} does not have a Stripe customer id configured."
  end

  defp error_message({:ambiguous_stripe_customer, candidates}, account) do
    formatted =
      candidates
      |> Enum.take(5)
      |> Enum.map_join("\n", fn customer ->
        "- #{customer.name || "(unnamed)"} (#{customer.id})#{format_email(customer.email)}"
      end)

    "Multiple Stripe customers look like #{account.name}. Update the account's Stripe customer id manually, or rename the account so the match is unambiguous. Candidates:\n#{formatted}"
  end

  defp error_message({:account_update_failed, _reason}, account) do
    "Found a Stripe customer for #{account.name} but could not save the id on the account."
  end

  defp error_message(:signed_order_form_not_found, account) do
    "No signed order form was found for #{account.name}."
  end

  defp error_message(:missing_invoice_amount, account) do
    "The latest signed order form for #{account.name} does not include an invoice amount Atlas can extract."
  end

  defp error_message(:missing_invoice_currency, account) do
    "The latest signed order form for #{account.name} does not include an invoice currency Atlas can extract."
  end

  defp error_message(:missing_line_item_description, _account) do
    "One of the supplied line items is missing a description."
  end

  defp error_message(:invalid_line_items, _account) do
    "The supplied line items are malformed. Each item needs a description, amount, and currency."
  end

  defp error_message(:stripe_disabled, _account), do: "Stripe is not configured."

  defp error_message({:invoice_item, invoice_id, reason}, _account) do
    "Stripe created draft invoice #{invoice_id}, but Atlas could not attach its line items: #{inspect(reason)}"
  end

  defp error_message(reason, _account), do: "Could not create the Stripe draft invoice: #{inspect(reason)}"

  defp format_email(nil), do: ""
  defp format_email(""), do: ""
  defp format_email(email) when is_binary(email), do: " <#{email}>"
end
