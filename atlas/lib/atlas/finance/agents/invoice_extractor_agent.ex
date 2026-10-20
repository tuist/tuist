defmodule Atlas.Finance.Agents.InvoiceExtractorAgent do
  @moduledoc false

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.LLMs.Runner

  @impl true
  def tools, do: []

  @impl true
  def system_prompt do
    """
    You extract vendor invoice cost structure for Atlas.

    Return invoice header data and a granular cost breakdown grounded only in
    the invoice text. Split meaningful charges into line items. For each line
    item, assign a broad reusable cost category, not a vendor-specific label.
    Good categories include Cloud Infrastructure, Software, Payroll, Contractor,
    Legal, Accounting, Banking Fees, Travel, Hardware, Office, Marketing, Taxes,
    and Other Expense.

    Do not invent amounts, currencies, dates, or tax values. If the invoice has
    no clear line items but has a total, return one line item for the total using
    the best broad category. Use decimal strings for money.

    #{StyleGuide.prose_rules()}
    """
  end

  def extract(%Document{} = document, pages) when is_list(pages) do
    case Runner.fetch_config() do
      {:ok, llm} ->
        Sessions.run(
          __MODULE__,
          prompt(document, pages),
          Runner.client_opts(llm) ++ [max_turns: 4, load_project_instructions: false, output: output_schema()]
        )
        |> normalize_result(document)

      {:error, :llm_not_configured} ->
        {:ok, fallback(document)}
    end
  end

  def fallback_metadata(%Document{} = document), do: fallback(document)

  defp prompt(document, pages) do
    sample =
      pages
      |> Enum.take(12)
      |> Enum.map_join("\n\n", fn %DocumentPage{} = page ->
        "Page #{page.page_number}:\n#{String.slice(page.content, 0, 4_000)}"
      end)

    """
    Extract this vendor invoice.

    Filename: #{document.original_filename}
    Document title: #{document.title}
    Document date: #{format_date(document.document_date)}
    Existing attributes: #{JSON.encode!(document.attributes || %{})}

    Text:
    #{sample}
    """
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        vendor_name: %{type: "string"},
        invoice_number: %{type: "string"},
        invoice_date: %{type: "string"},
        due_date: %{type: "string"},
        period_start: %{type: "string"},
        period_end: %{type: "string"},
        total_amount_value: %{type: "string"},
        total_amount_currency: %{type: "string"},
        tax_amount_value: %{type: "string"},
        tax_amount_currency: %{type: "string"},
        confidence: %{type: "number"},
        metadata: %{type: "object"},
        line_items: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              description: %{type: "string"},
              category_name: %{type: "string"},
              cost_type: %{type: "string"},
              amount_value: %{type: "string"},
              amount_currency: %{type: "string"},
              quantity: %{type: "string"},
              unit_amount_value: %{type: "string"},
              unit_amount_currency: %{type: "string"},
              service_period_start: %{type: "string"},
              service_period_end: %{type: "string"},
              confidence: %{type: "number"},
              metadata: %{type: "object"}
            },
            required: ["description", "amount_value", "amount_currency"]
          }
        }
      },
      # `vendor_name` is intentionally not required. Models routinely omit it on
      # large, many-line-item invoices (cloud usage bills), and rejecting the
      # whole extraction there discards otherwise-valid line items — the single
      # biggest source of missing vendor cost. `normalize_invoice/2` backfills
      # the vendor from the source document when the model leaves it out.
      required: ["line_items"]
    }
  end

  defp normalize_result({:ok, result}, document) when is_map(result) do
    {:ok,
     %{
       invoice: normalize_invoice(result, document),
       line_items: normalize_line_items(value(result, :line_items))
     }}
  end

  defp normalize_result({:ok, _other}, document), do: {:ok, fallback(document)}
  defp normalize_result({:error, :llm_not_configured}, document), do: {:ok, fallback(document)}
  defp normalize_result({:error, reason}, _document), do: {:error, reason}

  defp fallback(%Document{} = document) do
    %{
      invoice: %{
        vendor_name: document_vendor(document),
        invoice_date: document.document_date,
        extracted_by_agent: "invoice_extractor_fallback",
        metadata: %{"fallback" => true}
      },
      line_items: []
    }
  end

  defp normalize_invoice(result, document) do
    %{
      vendor_name: invoice_vendor_name(result, document),
      invoice_number: clean_string(value(result, :invoice_number)),
      invoice_date: invoice_date(result, document),
      due_date: parse_date(value(result, :due_date)),
      period_start: parse_date(value(result, :period_start)),
      period_end: parse_date(value(result, :period_end)),
      total_amount_value: parse_decimal(value(result, :total_amount_value)),
      total_amount_currency: clean_currency(value(result, :total_amount_currency)),
      tax_amount_value: parse_decimal(value(result, :tax_amount_value)),
      tax_amount_currency: clean_currency(value(result, :tax_amount_currency)),
      confidence: parse_decimal(value(result, :confidence)),
      extracted_by_agent: "invoice_extractor",
      metadata: clean_map(value(result, :metadata))
    }
  end

  defp invoice_vendor_name(result, document), do: clean_string(value(result, :vendor_name)) || document_vendor(document)
  defp invoice_date(result, document), do: parse_date(value(result, :invoice_date)) || document.document_date

  defp normalize_line_items(values) when is_list(values) do
    values
    |> Enum.map(&normalize_line_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_line_items(_values), do: []

  defp normalize_line_item(value) when is_map(value) do
    with description when is_binary(description) <- clean_string(value(value, :description)),
         %Decimal{} = amount <- parse_decimal(value(value, :amount_value)),
         currency when is_binary(currency) <- clean_currency(value(value, :amount_currency)) do
      build_line_item(value, description, amount, currency)
    else
      _ -> nil
    end
  end

  defp normalize_line_item(_value), do: nil

  defp build_line_item(value, description, amount, currency) do
    %{
      description: description,
      category_name: clean_string(value(value, :category_name)),
      cost_type: clean_type(value(value, :cost_type)),
      amount_value: amount,
      amount_currency: currency,
      quantity: parse_decimal(value(value, :quantity)),
      unit_amount_value: parse_decimal(value(value, :unit_amount_value)),
      unit_amount_currency: clean_currency(value(value, :unit_amount_currency)),
      service_period_start: parse_date(value(value, :service_period_start)),
      service_period_end: parse_date(value(value, :service_period_end)),
      confidence: parse_decimal(value(value, :confidence)),
      metadata: clean_map(value(value, :metadata))
    }
  end

  defp value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, Atom.to_string(key)) || Map.get(map, key)

  defp document_vendor(%Document{correspondent: %{name: name}}) when is_binary(name), do: name
  defp document_vendor(%Document{title: title}) when is_binary(title), do: title
  defp document_vendor(%Document{original_filename: filename}) when is_binary(filename), do: filename
  defp document_vendor(_document), do: "Unknown vendor"

  defp clean_string(value) when is_binary(value) do
    value = String.trim(value)
    if value != "", do: value
  end

  defp clean_string(_value), do: nil

  defp clean_type(value) do
    value
    |> clean_string()
    |> case do
      nil -> nil
      type -> type |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
    end
  end

  defp clean_currency(value) do
    value
    |> clean_string()
    |> case do
      nil -> nil
      currency -> String.upcase(currency)
    end
  end

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp parse_decimal(%Decimal{} = value), do: value

  defp parse_decimal(value) when is_integer(value) or is_float(value) do
    value |> to_string() |> Decimal.new()
  rescue
    _ -> nil
  end

  defp parse_decimal(value) when is_binary(value) do
    value |> String.trim() |> String.replace(",", "") |> Decimal.new()
  rescue
    _ -> nil
  end

  defp parse_decimal(_value), do: nil

  defp clean_map(value) when is_map(value), do: value
  defp clean_map(_value), do: %{}

  defp format_date(nil), do: "unknown"
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
end
