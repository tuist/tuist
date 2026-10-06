defmodule Atlas.MCP.Tools.EditStripeDraftInvoice do
  @moduledoc """
  Edits an existing Stripe draft invoice for an account.

  Default behavior re-extracts line items from the account's most recent
  signed order form and attaches them. Also accepts optional fields to
  update on the invoice itself.
  """

  use Atlas.MCP.Tool,
    name: "edit_stripe_draft_invoice",
    schema: %{
      "type" => "object",
      "required" => ["stripe_invoice_id"],
      "properties" =>
        Atlas.MCP.AccountLookup.identifier_schema_properties()
        |> Map.merge(%{
          "stripe_invoice_id" => %{
            "type" => "string",
            "description" => "Existing Stripe draft invoice id, for example `in_1Abc...`."
          },
          "description" => %{
            "type" => "string",
            "description" => "Optional new value for the invoice's description field."
          },
          "footer" => %{
            "type" => "string",
            "description" => "Optional new value for the invoice's footer field."
          },
          "days_until_due" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Optional new payment-term length, in days from finalization."
          },
          "metadata" => %{
            "type" => "object",
            "description" =>
              "Optional metadata keys to set on the invoice. Stripe merges keys; existing keys not listed here keep their value.",
            "additionalProperties" => %{"type" => "string"}
          },
          "attach_order_form_line_items" => %{
            "type" => "boolean",
            "default" => true,
            "description" =>
              "When true (the default) Atlas re-extracts line items from the account's most recent signed order form and attaches them. Set to false to skip the order-form lookup and only update invoice fields. Ignored when `line_items` is supplied."
          },
          "line_items" => %{
            "type" => "array",
            "description" =>
              "Optional line items to attach to the invoice. When supplied, Atlas uses these instead of auto-extracting from the signed order form. Use this when the order form lives on pages the extractor does not scan or when the extracted amount is wrong.",
            "items" => Atlas.MCP.LineItems.schema_item()
          }
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
        "source_document" =>
          Atlas.MCP.Tool.nullable(%{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "title" => %{"type" => ["string", "null"]},
              "document_date" => %{"type" => ["string", "null"]},
              "url" => %{"type" => "string"}
            },
            "required" => ["id", "title", "document_date", "url"],
            "additionalProperties" => false
          }),
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
        "updated_invoice_fields" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => [
        "account",
        "source_document",
        "draft_invoice",
        "stripe_invoice",
        "line_items",
        "updated_invoice_fields"
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
      "Edit an existing Stripe draft invoice for an account. By default re-extracts line items from the account's latest signed order form in Atlas and attaches them to the invoice. Also accepts optional invoice fields to update (description, footer, days_until_due, metadata). Use this when a previous create_stripe_draft_invoice call left an invoice with missing or stale items, or when a teammate asks to edit an existing draft."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools"),
         {:ok, account} <- AccountLookup.resolve(args),
         {:ok, invoice_id} <- fetch_invoice_id(args) do
      edit_attrs = build_edit_attrs(args)

      account
      |> Accounts.edit_stripe_draft_invoice(invoice_id, edit_attrs)
      |> case do
        {:ok, result} -> {:ok, serialize_result(result)}
        {:error, reason} -> {:error, error_message(reason, account, invoice_id)}
      end
    end
  end

  defp fetch_invoice_id(args) do
    case args["stripe_invoice_id"] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, "stripe_invoice_id is required."}
          trimmed -> {:ok, trimmed}
        end

      _value ->
        {:error, "stripe_invoice_id is required."}
    end
  end

  defp build_edit_attrs(args) do
    %{}
    |> put_optional(:description, args["description"])
    |> put_optional(:footer, args["footer"])
    |> put_optional(:days_until_due, args["days_until_due"])
    |> put_optional(:metadata, normalize_metadata(args["metadata"]))
    |> put_attach_flag(args["attach_order_form_line_items"])
    |> put_line_items(args["line_items"])
  end

  defp put_line_items(attrs, items) when is_list(items) and items != [],
    do: Map.put(attrs, :line_items, LineItems.normalize(items))

  defp put_line_items(attrs, _items), do: attrs

  defp put_optional(attrs, _key, nil), do: attrs
  defp put_optional(attrs, _key, ""), do: attrs
  defp put_optional(attrs, key, value), do: Map.put(attrs, key, value)

  defp put_attach_flag(attrs, value) when is_boolean(value), do: Map.put(attrs, :attach_order_form_line_items, value)
  defp put_attach_flag(attrs, _value), do: attrs

  defp normalize_metadata(nil), do: nil

  defp normalize_metadata(metadata) when is_map(metadata) and map_size(metadata) > 0 do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_metadata(_metadata), do: nil

  defp serialize_result(%{
         account: account,
         source_document: source_document,
         draft_invoice: %Invoice{} = invoice,
         stripe_invoice: %Stripe.Invoice{} = stripe_invoice,
         line_items: line_items,
         updated_invoice_fields: updated_invoice_fields
       }) do
    %{
      account: %{
        id: account.id,
        account_key: account.account_key,
        name: account.name,
        stripe_customer_id: account.stripe_customer_id
      },
      source_document: serialize_source_document(source_document),
      draft_invoice: AccountSerializer.invoice(invoice),
      stripe_invoice: %{
        id: stripe_invoice.id,
        status: stripe_invoice.status,
        dashboard_url: stripe_invoice.dashboard_url,
        hosted_url: stripe_invoice.hosted_url,
        pdf_url: stripe_invoice.pdf_url
      },
      line_items: Enum.map(line_items, &serialize_line_item/1),
      updated_invoice_fields: Enum.map(updated_invoice_fields, &Atom.to_string/1)
    }
  end

  defp serialize_source_document(%Document{} = document) do
    %{
      id: document.id,
      title: document.title,
      document_date: Tool.iso8601(document.document_date),
      url: Tool.document_url(document)
    }
  end

  defp serialize_source_document(_document), do: nil

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

  defp error_message(:signed_order_form_not_found, account, _invoice_id) do
    "No signed order form was found for #{account.name}."
  end

  defp error_message(:missing_invoice_amount, account, _invoice_id) do
    "The latest signed order form for #{account.name} does not include an invoice amount Atlas can extract."
  end

  defp error_message(:missing_invoice_currency, account, _invoice_id) do
    "The latest signed order form for #{account.name} does not include an invoice currency Atlas can extract."
  end

  defp error_message(:missing_invoice_customer, _account, invoice_id) do
    "Stripe invoice #{invoice_id} does not reference a customer Atlas could read."
  end

  defp error_message(:stripe_disabled, _account, _invoice_id), do: "Stripe is not configured."

  defp error_message(:missing_line_item_description, _account, _invoice_id) do
    "One of the supplied line items is missing a description."
  end

  defp error_message(:invalid_line_items, _account, _invoice_id) do
    "The supplied line items are malformed. Each item needs a description, amount, and currency."
  end

  defp error_message({:invoice_item, invoice_id, reason}, _account, _passed_invoice_id) do
    "Atlas could not attach the line items to #{invoice_id}: #{inspect(reason)}"
  end

  defp error_message(reason, _account, invoice_id) do
    "Could not edit Stripe invoice #{invoice_id}: #{inspect(reason)}"
  end
end
