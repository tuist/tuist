defmodule Atlas.Finance.Agents.CostDigestAgent do
  @moduledoc """
  Agent that writes leadership cost digests for deterministic Slack rendering.
  """

  alias Atlas.Accounts.Amounts
  alias Atlas.Agents.StyleGuide
  alias Atlas.Finance
  alias Atlas.Finance.Config
  alias Atlas.Finance.Invoice
  alias Atlas.LLMs.Runner

  @default_invoice_limit 25
  @high_concentration_percent Decimal.new("60")
  @material_weekly_increase_percent Decimal.new("20")

  def weekly_context(opts \\ []) do
    now =
      opts
      |> Keyword.get(:now, DateTime.utc_now())
      |> DateTime.truncate(:second)

    current_week_start = now |> DateTime.to_date() |> monday_of_week() |> utc_start_of_day()
    period_start = DateTime.add(current_week_start, -7 * 24 * 60 * 60, :second)
    previous_period_start = DateTime.add(current_week_start, -14 * 24 * 60 * 60, :second)

    %{
      cadence: :weekly,
      title: "Weekly cost digest",
      currency: Config.report_currency(),
      period_start: period_start,
      period_end: current_week_start,
      comparison_period_start: previous_period_start,
      comparison_period_end: period_start
    }
  end

  def daily_context(opts \\ []) do
    now =
      opts
      |> Keyword.get(:now, DateTime.utc_now())
      |> DateTime.truncate(:second)

    today_start = now |> DateTime.to_date() |> utc_start_of_day()
    period_start = DateTime.add(today_start, -24 * 60 * 60, :second)
    comparison_period_start = DateTime.add(period_start, -30 * 24 * 60 * 60, :second)

    %{
      cadence: :daily,
      title: "Daily cost check",
      currency: Config.report_currency(),
      period_start: period_start,
      period_end: today_start,
      comparison_period_start: comparison_period_start,
      comparison_period_end: period_start
    }
  end

  def summarize(context) when is_map(context) do
    with {:ok, llm} <- Runner.fetch_config() do
      Condukt.run(
        build_prompt(context),
        Runner.client_opts(llm) ++
          [
            system_prompt: system_prompt(),
            tools: tools(),
            load_project_instructions: false,
            max_turns: 8,
            output: output_schema()
          ]
      )
      |> normalize_result(context)
    end
  end

  def fallback(context) when is_map(context) do
    current = Finance.vendor_cost_analytics(analytics_opts(context.period_start, context.period_end, context.currency))

    comparison =
      Finance.vendor_cost_analytics(
        analytics_opts(context.comparison_period_start, context.comparison_period_end, context.currency)
      )

    summary = fallback_summary(context, current, comparison)
    concerns = fallback_concerns(context, current, comparison)

    %{
      fallback_text: "#{context.title}: #{summary}",
      blocks: fallback_blocks(context, current, comparison, summary),
      readout: %{summary: summary, concerns: concerns, next_steps: fallback_next_steps(concerns)}
    }
  end

  def system_prompt do
    """
    You write cost digests for company leadership.

    You have tools to inspect Atlas vendor invoice costs. Use them before writing:
    - get_vendor_cost_analytics for period spend, vendors, categories, concentration, monthly spend, and expenses.
    - list_finance_invoices for invoice and line-item detail.

    Return structured cost-digest copy. Atlas renders it into Slack blocks.

    Your job:
    - For weekly digests, summarize the last completed week of costs and compare it with the previous completed week.
    - For daily checks, inspect yesterday's new costs and compare them with the prior 30 days.
    - Raise anything leadership should worry about, including unusual vendor spend, new or concentrated spend, cost category spikes, invoice line items that look surprising, missing breakdowns, or repeated needs-review invoices.
    - Say plainly when there is no material concern.
    - Include only facts grounded in the tool results or supplied reporting windows.

    Steering:
    - Be specific about amounts, vendors, categories, invoice dates, and line items when evidence supports it.
    - Do not invent causes, owners, commitments, forecasts, or missing data.
    - Keep Slack copy compact. Avoid markdown tables.
    - Use plain text without markdown formatting.
    - Do not use emoji.
    - Use "-" instead of em dashes.

    #{StyleGuide.prose_rules()}
    """
  end

  defp tools do
    [
      vendor_cost_analytics_tool(),
      list_finance_invoices_tool()
    ]
  end

  defp vendor_cost_analytics_tool do
    Condukt.tool(
      name: "get_vendor_cost_analytics",
      description:
        "Get vendor invoice cost analytics for a date range, including spend, vendors, categories, monthly spend, and expenses.",
      parameters: %{
        type: "object",
        properties: %{
          date_from: %{type: "string", description: "Inclusive ISO-8601 date."},
          date_to: %{type: "string", description: "Inclusive ISO-8601 date."},
          currency: %{type: "string", description: "Optional invoice currency to report, for example USD or EUR."}
        },
        required: ["date_from", "date_to"]
      },
      call: fn params, _ctx ->
        analytics =
          params
          |> date_filter_opts()
          |> Finance.vendor_cost_analytics()
          |> serialize_analytics()

        {:ok, analytics}
      end
    )
  end

  defp list_finance_invoices_tool do
    Condukt.tool(
      name: "list_finance_invoices",
      description: "List vendor invoices with extracted line items for a date range.",
      parameters: %{
        type: "object",
        properties: %{
          date_from: %{type: "string", description: "Inclusive ISO-8601 date."},
          date_to: %{type: "string", description: "Inclusive ISO-8601 date."},
          vendor: %{type: "string"},
          status: %{type: "string", enum: ["extracted", "needs_review", "failed"]},
          page_size: %{type: "integer", minimum: 1, maximum: 50}
        },
        required: ["date_from", "date_to"]
      },
      call: fn params, _ctx ->
        invoices =
          params
          |> invoice_opts()
          |> Finance.list_invoices()
          |> Enum.map(&serialize_invoice/1)

        {:ok, %{invoices: invoices, count: length(invoices)}}
      end
    )
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        fallback_text: %{
          type: "string",
          description: "One short sentence for Slack notifications.",
          maxLength: 240
        },
        summary: %{
          type: "string",
          description: "A concise leadership readout grounded in the cost data.",
          maxLength: 1_200
        },
        concerns: %{
          type: "array",
          description: "Concrete issues to watch, or an empty list when there are no material concerns.",
          maxItems: 5,
          items: %{type: "string", maxLength: 400}
        },
        next_steps: %{
          type: "array",
          description: "Concrete follow-ups, or an empty list when no follow-up is warranted.",
          maxItems: 4,
          items: %{type: "string", maxLength: 300}
        }
      },
      required: ["fallback_text", "summary", "concerns", "next_steps"]
    }
  end

  defp build_prompt(context) do
    """
    Write the #{context.title} for leadership.

    Cadence: #{context.cadence}
    Current reporting window: #{format_date(context.period_start)} to #{format_date(DateTime.add(context.period_end, -1, :second))}
    Comparison window: #{format_date(context.comparison_period_start)} to #{format_date(DateTime.add(context.comparison_period_end, -1, :second))}
    Report currency: #{context.currency}

    Use get_vendor_cost_analytics for both windows. Use list_finance_invoices for the current window and, when needed, specific vendors or needs-review invoices.

    Output:
    - fallback_text: one short sentence that summarizes the cost state.
    - summary: a compact leadership readout.
    - concerns: concrete issues to watch, or [] when there are no material concerns.
    - next_steps: concrete follow-ups, or [] when no follow-up is warranted.
    """
  end

  defp normalize_result({:ok, result}, context) when is_map(result) do
    with {:ok, fallback_text} <- normalize_text(Map.get(result, "fallback_text") || Map.get(result, :fallback_text)),
         {:ok, summary} <- normalize_text(Map.get(result, "summary") || Map.get(result, :summary)),
         {:ok, concerns} <- normalize_text_list(Map.get(result, "concerns") || Map.get(result, :concerns) || []),
         {:ok, next_steps} <-
           normalize_text_list(Map.get(result, "next_steps") || Map.get(result, :next_steps) || []) do
      readout = %{summary: summary, concerns: concerns, next_steps: next_steps}

      {:ok, %{fallback_text: fallback_text, blocks: generated_blocks(context, readout), readout: readout}}
    else
      :error -> {:error, :unexpected_result}
    end
  end

  defp normalize_result({:ok, _other}, _context), do: {:error, :unexpected_result}
  defp normalize_result({:error, reason}, _context), do: {:error, reason}

  defp analytics_opts(period_start, period_end, currency) do
    [
      date_from: DateTime.to_date(period_start),
      date_to: period_end |> DateTime.add(-1, :second) |> DateTime.to_date(),
      currency: currency
    ]
  end

  defp fallback_summary(_context, %{invoice_count: 0}, _comparison) do
    "No vendor invoices were recorded in the reporting window."
  end

  defp fallback_summary(context, current, comparison) do
    spend = Amounts.format(current.total_spend_value, current.currency)
    top_vendor = current.top_vendor && current.top_vendor.vendor_name
    comparison_text = comparison_text(context, current, comparison)

    vendor_text =
      case top_vendor do
        nil -> ""
        vendor -> " The largest vendor was #{vendor}."
      end

    "#{spend} across #{current.invoice_count} invoices from #{current.vendor_count} vendors.#{vendor_text}#{comparison_text}"
  end

  defp comparison_text(%{cadence: :weekly}, current, comparison) do
    case percent_change(current.total_spend_value, comparison.total_spend_value) do
      nil -> ""
      change -> " That is #{format_percent_change(change)} compared with the previous week."
    end
  end

  defp comparison_text(%{cadence: :daily}, _current, comparison) do
    " The prior 30 days contained #{Amounts.format(comparison.total_spend_value, comparison.currency)} of vendor invoices."
  end

  defp fallback_blocks(context, current, comparison, summary) do
    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => context.title, "emoji" => true}
      },
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "mrkdwn",
            "text" =>
              "#{format_date(context.period_start)} to #{format_date(DateTime.add(context.period_end, -1, :second))} | Report currency #{context.currency}"
          }
        ]
      },
      %{
        "type" => "section",
        "text" => %{"type" => "mrkdwn", "text" => "*Summary*\n#{escape_mrkdwn(summary)}"}
      },
      metrics_block(context, current, comparison),
      top_vendors_block(current),
      concerns_block(context, current, comparison),
      %{
        "type" => "context",
        "elements" => [%{"type" => "mrkdwn", "text" => "Generated by Atlas cost monitoring"}]
      }
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp generated_blocks(context, readout) do
    [
      generated_header_block(context),
      generated_context_block(context),
      generated_summary_block(readout.summary),
      generated_concerns_block(readout.concerns),
      generated_next_steps_block(readout.next_steps),
      %{
        "type" => "context",
        "elements" => [%{"type" => "mrkdwn", "text" => "Generated by Atlas cost monitoring"}]
      }
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp generated_header_block(context) do
    title =
      case context.cadence do
        :daily -> "#{context.title} - #{format_date(context.period_start)}"
        _cadence -> context.title
      end

    %{
      "type" => "header",
      "text" => %{"type" => "plain_text", "text" => title, "emoji" => false}
    }
  end

  defp generated_context_block(context) do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" =>
            "*Reporting window*\n#{format_date(context.period_start)} to #{format_date(DateTime.add(context.period_end, -1, :second))}"
        },
        %{
          "type" => "mrkdwn",
          "text" =>
            "*Comparison window*\n#{format_date(context.comparison_period_start)} to #{format_date(DateTime.add(context.comparison_period_end, -1, :second))}"
        },
        %{"type" => "mrkdwn", "text" => "*Currency*\n#{escape_mrkdwn(context.currency)}"}
      ]
    }
  end

  defp generated_summary_block(summary) do
    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Summary*\n#{escape_mrkdwn(summary)}"}
    }
  end

  defp generated_concerns_block([]) do
    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Concerns*\nNo material concerns detected."}
    }
  end

  defp generated_concerns_block(concerns) do
    text = Enum.map_join(concerns, "\n", &"- #{escape_mrkdwn(&1)}")

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Concerns*\n#{text}"}
    }
  end

  defp generated_next_steps_block([]), do: nil

  defp generated_next_steps_block(next_steps) do
    text = Enum.map_join(next_steps, "\n", &"- #{escape_mrkdwn(&1)}")

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Next steps*\n#{text}"}
    }
  end

  defp metrics_block(context, current, comparison) do
    %{
      "type" => "section",
      "fields" => [
        metric_field("Current spend", Amounts.format(current.total_spend_value, current.currency)),
        metric_field(comparison_label(context), Amounts.format(comparison.total_spend_value, comparison.currency)),
        metric_field("Invoices", Integer.to_string(current.invoice_count)),
        metric_field("Vendors", Integer.to_string(current.vendor_count)),
        metric_field("Top-vendor concentration", format_percent(current.concentration_percent)),
        metric_field("Needs review", Integer.to_string(current.needs_review_count))
      ]
    }
  end

  defp comparison_label(%{cadence: :weekly}), do: "Previous week"
  defp comparison_label(%{cadence: :daily}), do: "Prior 30 days"

  defp metric_field(label, value) do
    %{"type" => "mrkdwn", "text" => "*#{label}*\n#{escape_mrkdwn(value)}"}
  end

  defp top_vendors_block(%{vendors: []}), do: nil

  defp top_vendors_block(current) do
    vendors =
      current.vendors
      |> Enum.take(5)
      |> Enum.map_join("\n", fn vendor ->
        "- *#{escape_mrkdwn(vendor.vendor_name)}*: #{Amounts.format(vendor.total_amount_value, vendor.total_amount_currency)}"
      end)

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Largest vendors*\n#{vendors}"}
    }
  end

  defp concerns_block(context, current, comparison) do
    concerns = fallback_concerns(context, current, comparison)

    text =
      case concerns do
        [] ->
          "No material concerns detected."

        concerns ->
          Enum.map_join(concerns, "\n", fn concern -> "- #{escape_mrkdwn(concern)}" end)
      end

    %{
      "type" => "section",
      "text" => %{"type" => "mrkdwn", "text" => "*Concerns*\n#{text}"}
    }
  end

  defp fallback_concerns(context, current, comparison) do
    [
      review_concern(current),
      concentration_concern(current),
      weekly_increase_concern(context, current, comparison)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp fallback_next_steps([]), do: []

  defp fallback_next_steps(_concerns) do
    ["Review the underlying invoices and assign an owner when follow-up is warranted."]
  end

  defp review_concern(%{needs_review_count: count}) when count > 0 do
    "#{count} #{pluralize(count, "invoice needs", "invoices need")} extraction review."
  end

  defp review_concern(_current), do: nil

  defp concentration_concern(%{concentration_percent: %Decimal{} = concentration, top_vendor: top_vendor}) do
    if Decimal.compare(concentration, @high_concentration_percent) in [:eq, :gt] and top_vendor do
      "#{top_vendor.vendor_name} represents #{format_percent(concentration)} of spend in this window."
    end
  end

  defp concentration_concern(_current), do: nil

  defp weekly_increase_concern(%{cadence: :weekly}, current, comparison) do
    case percent_change(current.total_spend_value, comparison.total_spend_value) do
      %Decimal{} = change ->
        if Decimal.compare(change, @material_weekly_increase_percent) in [:eq, :gt] do
          "Vendor invoice spend increased #{format_percent(change)} compared with the previous week."
        end

      nil ->
        nil
    end
  end

  defp weekly_increase_concern(_context, _current, _comparison), do: nil

  defp percent_change(%Decimal{} = current, %Decimal{} = previous) do
    if Decimal.positive?(previous) do
      current
      |> Decimal.sub(previous)
      |> Decimal.div(previous)
      |> Decimal.mult(100)
    end
  end

  defp percent_change(_current, _previous), do: nil

  defp format_percent(nil), do: "Not available"
  defp format_percent(%Decimal{} = percent), do: "#{percent |> Decimal.round(1) |> Decimal.to_string(:normal)}%"

  defp format_percent_change(%Decimal{} = percent) do
    direction = if Decimal.negative?(percent), do: "lower", else: "higher"
    "#{percent |> Decimal.abs() |> format_percent()} #{direction}"
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp escape_mrkdwn(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp normalize_text_list(values) when is_list(values) do
    values =
      Enum.flat_map(values, fn value ->
        case normalize_text(value) do
          {:ok, text} -> [text]
          :error -> []
        end
      end)

    {:ok, values}
  end

  defp normalize_text_list(_values), do: :error

  defp normalize_text(text) when is_binary(text) do
    text =
      text
      |> String.replace("\\r\\n", "\n")
      |> String.replace("\\n", "\n")
      |> String.replace("\\r", "\n")
      |> String.trim()

    case text do
      "" -> :error
      text -> {:ok, text}
    end
  end

  defp normalize_text(_text), do: :error

  defp date_filter_opts(params) do
    [
      date_from: parse_date(Map.get(params, "date_from")),
      date_to: parse_date(Map.get(params, "date_to")),
      currency: present(params, "currency")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp invoice_opts(params) do
    date_filter_opts(params)
    |> Keyword.merge(
      vendor: present(params, "vendor"),
      status: present(params, "status"),
      limit: invoice_limit(params)
    )
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp invoice_limit(params) do
    case Map.get(params, "page_size") do
      value when is_integer(value) and value > 0 -> min(value, 50)
      _value -> @default_invoice_limit
    end
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp present(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> value
      _value -> nil
    end
  end

  defp serialize_analytics(analytics) do
    %{
      currency: analytics.currency,
      default_currency: analytics.default_currency,
      available_currencies: Enum.map(analytics.available_currencies, &serialize_currency_summary/1),
      total_spend_value: decimal_to_string(analytics.total_spend_value),
      invoice_count: analytics.invoice_count,
      vendor_count: analytics.vendor_count,
      needs_review_count: analytics.needs_review_count,
      concentration_percent: decimal_to_string(analytics.concentration_percent),
      top_vendor: analytics.top_vendor && serialize_vendor(analytics.top_vendor),
      vendors: Enum.map(analytics.vendors, &serialize_vendor/1),
      categories: Enum.map(analytics.categories, &serialize_category/1),
      monthly_spend: Enum.map(analytics.monthly_spend, &serialize_monthly_spend/1),
      expenses: Enum.map(analytics.expenses, &serialize_expense/1)
    }
  end

  defp serialize_currency_summary(currency_summary) do
    %{
      currency: currency_summary.currency,
      total_spend_value: decimal_to_string(currency_summary.total_spend_value),
      invoice_count: currency_summary.invoice_count,
      vendor_count: currency_summary.vendor_count
    }
  end

  defp serialize_vendor(vendor) do
    %{
      vendor_name: vendor.vendor_name,
      total_amount_value: decimal_to_string(vendor.total_amount_value),
      total_amount_currency: vendor.total_amount_currency,
      invoice_count: vendor.invoice_count,
      line_item_count: vendor.line_item_count,
      needs_review_count: vendor.needs_review_count,
      last_invoice_date: format_date(vendor.last_invoice_date),
      categories: vendor.categories
    }
  end

  defp serialize_category(category) do
    %{
      category_name: category.category_name,
      amount_value: decimal_to_string(category.amount_value),
      amount_currency: category.amount_currency,
      line_item_count: category.line_item_count
    }
  end

  defp serialize_monthly_spend(monthly_spend) do
    %{
      date: format_date(monthly_spend.date),
      amount_value: decimal_to_string(monthly_spend.amount_value)
    }
  end

  defp serialize_expense(expense) do
    %{
      vendor_name: expense.vendor_name,
      invoice_number: expense.invoice_number,
      invoice_date: format_date(expense.invoice_date),
      status: expense.status,
      total_amount_value: decimal_to_string(expense.total_amount_value),
      total_amount_currency: expense.total_amount_currency,
      categories: expense.categories,
      line_items: Enum.map(expense.line_items, &serialize_line_item/1)
    }
  end

  defp serialize_invoice(%Invoice{} = invoice) do
    %{
      id: invoice.id,
      vendor_name: invoice.vendor_name,
      invoice_number: invoice.invoice_number,
      invoice_date: format_date(invoice.invoice_date),
      due_date: format_date(invoice.due_date),
      status: invoice.status,
      total_amount_value: decimal_to_string(invoice.total_amount_value),
      total_amount_currency: invoice.total_amount_currency,
      source: invoice_source(invoice),
      line_items: Enum.map(invoice.line_items, &serialize_line_item/1)
    }
  end

  defp serialize_line_item(line_item) do
    %{
      description: line_item.description,
      category_name: (line_item.category && line_item.category.name) || line_item.cost_type || "Uncategorized",
      amount_value: decimal_to_string(line_item.amount_value),
      amount_currency: line_item.amount_currency
    }
  end

  defp invoice_source(%Invoice{document: %{source: source}}), do: source
  defp invoice_source(%Invoice{metadata: %{"source" => source}}), do: source
  defp invoice_source(_invoice), do: nil

  defp monday_of_week(%Date{} = date), do: Date.add(date, -(Date.day_of_week(date) - 1))
  defp utc_start_of_day(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()
  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value)
  defp decimal_to_string(value), do: value
end
