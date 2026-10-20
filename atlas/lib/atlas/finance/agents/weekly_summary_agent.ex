defmodule Atlas.Finance.Agents.WeeklySummaryAgent do
  @moduledoc """
  Agent that writes financial pulse checks for leadership.
  """

  alias Atlas.Accounts.Amounts
  alias Atlas.Agents.StyleGuide
  alias Atlas.Finance
  alias Atlas.Finance.Config
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction
  alias Atlas.LLMs.Runner

  @default_transaction_limit 50
  @critical_runway_months Decimal.new("6")
  @warning_runway_months Decimal.new("12")
  @stale_sync_seconds 24 * 60 * 60
  @cost_history_months 3

  def context(opts \\ []) do
    cadence = Keyword.get(opts, :cadence, :weekly)

    now =
      opts
      |> Keyword.get(:now, DateTime.utc_now())
      |> DateTime.truncate(:second)

    {period_start, period_end, previous_period_start} = periods(cadence, now)

    %{
      cadence: cadence,
      currency: Config.report_currency(),
      period_start: period_start,
      period_end: period_end,
      previous_period_start: previous_period_start,
      previous_period_end: period_start
    }
  end

  def summarize(context) when is_map(context) do
    with {:ok, llm} <- Runner.fetch_config() do
      Condukt.run(
        build_prompt(context),
        Runner.client_opts(llm) ++
          [
            system_prompt: system_prompt(),
            tools: tools(context),
            load_project_instructions: false,
            max_turns: 8,
            output: output_schema()
          ]
      )
      |> normalize_result()
    end
  end

  def build_report(context, readout) when is_map(context) and is_map(readout) do
    overview = Finance.overview()
    transactions = report_transactions(context)
    cost_history = expense_history(context)

    context
    |> Map.put(:overview, overview)
    |> Map.put(:readout, readout)
    |> Map.put(:status, report_status(readout.concerns))
    |> Map.put(:transaction_count, length(transactions))
    |> Map.put(:top_transactions, top_transactions(transactions))
    |> Map.put(:cost_history, cost_history)
  end

  def fallback(context) when is_map(context) do
    overview = Finance.overview()
    transactions = report_transactions(context)
    cost_history = expense_history(context)
    concerns = fallback_concerns(overview)

    context
    |> Map.put(:overview, overview)
    |> Map.put(:status, report_status(concerns))
    |> Map.put(:transaction_count, length(transactions))
    |> Map.put(:top_transactions, top_transactions(transactions))
    |> Map.put(:cost_history, cost_history)
    |> Map.put(:readout, %{
      headline: fallback_headline(cadence(context), concerns),
      summary: fallback_summary(overview),
      concerns: concerns,
      next_steps: fallback_next_steps(overview)
    })
  end

  def system_prompt do
    """
    You write financial pulse checks for company leadership.

    You have tools to inspect Atlas finance data. Use them before writing:
    - get_finance_overview for cash, burn, runway, projections, and sync freshness.
    - list_finance_transactions for recent transactions and unusual costs.
    - get_finance_expense_history for a weekly pulse's exact three-month cost history, including monthly totals and categories.

    Your job:
    - Produce a leadership-ready narrative explaining what changed, what drove it, and what to do next.
    - Raise anything concerning, such as rising costs, unusual costs, first-time costs, runway pressure, sync freshness issues, or unexpected transaction patterns.
    - Mention when there is no material concern.
    - Include only facts grounded in the tool results or supplied reporting window.

    Steering:
    - Be specific about amounts, categories, counterparties, dates, and direction when evidence supports it.
    - Do not invent causes, owners, commitments, forecasts, or missing data.
    - Avoid generic advice. If a follow-up is useful, make it concrete and tied to the observed data.
    - For weekly pulses, explain how costs have evolved across the supplied three-month history. Call out meaningful month-to-month changes and their largest categories when the data supports it.
    - Keep the summary concise enough for Slack: lead with the most important change, then give the cash, burn, runway, and cost-trend context that makes it meaningful.
    - Write a two-paragraph executive summary, then distinct key drivers, risks, and practical next steps. Do not repeat the same figures or advice in every section.
    - Investigate unusual movements with transaction searches, including possible matching transfers. Treat a pass-through or one-off classification as a hypothesis unless the records establish it.
    - Never infer pending payroll, future obligations, or adjusted burn from patterns alone. State what needs confirmation.
    - Label partial months and incomplete coverage. Do not compare a partial month with a full month as if they covered equal periods.
    - Transaction lists are limited samples, not exact totals. Never sum them to claim period revenue, expenses, or percentage changes.
    - Return plain prose in the structured fields. Atlas renders it into Slack blocks with bold headings and bullet lists.
    - Do not include markdown headings, tables, pipe-separated metrics, HTML, links, or formatting markers. Avoid acronyms.
    - Keep the daily pulse shorter, with only the drivers relevant to that day.

    #{StyleGuide.prose_rules()}
    """
  end

  defp tools(context) do
    [
      get_finance_overview_tool(),
      list_finance_transactions_tool()
    ]
    |> maybe_add_expense_history_tool(context)
  end

  defp maybe_add_expense_history_tool(tools, %{cadence: :weekly} = context) do
    tools ++ [get_finance_expense_history_tool(context)]
  end

  defp maybe_add_expense_history_tool(tools, _context), do: tools

  defp get_finance_overview_tool do
    Condukt.tool(
      name: "get_finance_overview",
      description:
        "Get cash, burn, runway, projections, account counts, transaction counts, sources, and sync freshness.",
      parameters: %{type: "object", properties: %{}},
      call: fn _params, _ctx ->
        overview = Finance.overview()
        sources = Finance.list_sources() |> Enum.map(&serialize_source/1)

        {:ok,
         %{
           overview: serialize_overview(overview),
           sources: sources,
           source_count: length(sources)
         }}
      end
    )
  end

  defp list_finance_transactions_tool do
    Condukt.tool(
      name: "list_finance_transactions",
      description:
        "List normalized finance transactions with filters for dates, direction, status, kind, currency, and search.",
      parameters: %{
        type: "object",
        properties: %{
          date_from: %{type: "string", description: "Inclusive ISO-8601 date or datetime lower bound."},
          date_to: %{type: "string", description: "Inclusive ISO-8601 date or datetime upper bound."},
          direction: %{type: "string", enum: ["credit", "debit"]},
          status: %{type: "string"},
          kind: %{type: "string"},
          currency: %{type: "string"},
          query: %{type: "string"},
          page_size: %{type: "integer", minimum: 1, maximum: 100}
        }
      },
      call: fn params, _ctx ->
        transactions =
          params
          |> list_opts()
          |> Finance.list_transactions()
          |> Enum.map(&serialize_transaction/1)

        {:ok, %{transactions: transactions, count: length(transactions)}}
      end
    )
  end

  defp get_finance_expense_history_tool(context) do
    Condukt.tool(
      name: "get_finance_expense_history",
      description:
        "Get an exact three-month history of cash expenses, grouped by calendar month with category totals and coverage details.",
      parameters: %{type: "object", properties: %{}},
      call: fn _params, _ctx ->
        {:ok, context |> expense_history() |> serialize_expense_history()}
      end
    )
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        headline: %{type: "string", maxLength: 150, description: "Short Slack header for the financial pulse."},
        summary: %{
          type: "string",
          maxLength: 1800,
          description: "Two short paragraphs: the main change and its cash, burn, and runway implications."
        },
        drivers: %{
          type: "array",
          maxItems: 4,
          description:
            "Key factors driving the numbers, with amounts, dates, comparisons, and evidence. Do not repeat the summary.",
          items: %{
            type: "object",
            properties: %{
              title: %{type: "string", maxLength: 120},
              detail: %{type: "string", maxLength: 900}
            },
            required: ["title", "detail"]
          }
        },
        concerns: %{
          type: "array",
          maxItems: 4,
          description: "Concrete concerns grounded in the finance data. Empty when there are no material concerns.",
          items: %{
            type: "object",
            properties: %{
              severity: %{type: "string", enum: ["info", "warning", "critical"]},
              title: %{type: "string", maxLength: 120},
              detail: %{type: "string", maxLength: 900}
            },
            required: ["severity", "title", "detail"]
          }
        },
        next_steps: %{
          type: "array",
          maxItems: 4,
          description: "Concrete follow-ups for leadership, if any.",
          items: %{type: "string", maxLength: 900}
        }
      },
      required: ["headline", "summary", "drivers", "concerns", "next_steps"]
    }
  end

  defp build_prompt(context) do
    """
    Write the #{cadence_label(cadence(context))} finance summary for leadership.

    Reporting window:
    - current_period: #{format_date(context.period_start)} to #{format_date(DateTime.add(context.period_end, -1, :second))}
    - comparison_period: #{format_date(context.previous_period_start)} to #{format_date(DateTime.add(context.previous_period_end, -1, :second))}
    - report_currency: #{context.currency}

    Use the tools to inspect the financial situation and compare the current period with the comparison period before producing the final answer.
    #{cost_history_prompt(context)}

    Output:
    - headline: short, suitable for a Slack header.
    - summary: two short paragraphs explaining the financial position and the most important change.
    - drivers: up to four distinct factors explaining the numbers, grounded in inspected records.
    - concerns: concrete issues to watch, or [] if no material concerns.
    - next_steps: concrete follow-ups, or [] if no follow-up is warranted.
    """
  end

  defp normalize_result({:ok, result}) when is_map(result) do
    with {:ok, headline} <- normalize_text(Map.get(result, "headline") || Map.get(result, :headline)),
         {:ok, summary} <- normalize_text(Map.get(result, "summary") || Map.get(result, :summary)),
         {:ok, drivers} <- normalize_drivers(Map.get(result, "drivers") || Map.get(result, :drivers) || []),
         {:ok, concerns} <- normalize_concerns(Map.get(result, "concerns") || Map.get(result, :concerns) || []),
         {:ok, next_steps} <- normalize_next_steps(Map.get(result, "next_steps") || Map.get(result, :next_steps) || []) do
      validate_readout(%{
        headline: headline,
        summary: summary,
        drivers: drivers,
        concerns: concerns,
        next_steps: next_steps
      })
    else
      :error -> {:error, :unexpected_result}
    end
  end

  defp normalize_result({:ok, _other}), do: {:error, :unexpected_result}
  defp normalize_result({:error, reason}), do: {:error, reason}

  defp validate_readout(readout) do
    if within_limits?(readout), do: {:ok, readout}, else: {:error, :unexpected_result}
  end

  defp within_limits?(readout) do
    String.length(readout.headline) <= 150 and String.length(readout.summary) <= 1800 and
      length(readout.drivers) <= 4 and length(readout.concerns) <= 4 and length(readout.next_steps) <= 4 and
      Enum.all?(readout.drivers ++ readout.concerns, fn finding ->
        String.length(finding.title) <= 120 and String.length(finding.detail) <= 900
      end) and Enum.all?(readout.next_steps, &(String.length(&1) <= 900))
  end

  defp normalize_drivers(drivers) when is_list(drivers) do
    Enum.reduce_while(drivers, {:ok, []}, fn
      driver, {:ok, acc} when is_map(driver) ->
        with {:ok, title} <- normalize_text(Map.get(driver, "title") || Map.get(driver, :title)),
             {:ok, detail} <- normalize_text(Map.get(driver, "detail") || Map.get(driver, :detail)) do
          {:cont, {:ok, acc ++ [%{title: title, detail: detail}]}}
        else
          _ -> {:halt, :error}
        end

      _, _ ->
        {:halt, :error}
    end)
  end

  defp normalize_drivers(_drivers), do: :error

  defp normalize_concerns(concerns) when is_list(concerns) do
    concerns =
      concerns
      |> Enum.flat_map(fn concern ->
        severity = Map.get(concern, "severity") || Map.get(concern, :severity) || "info"
        title = Map.get(concern, "title") || Map.get(concern, :title)
        detail = Map.get(concern, "detail") || Map.get(concern, :detail)

        with severity when severity in ["info", "warning", "critical"] <- severity,
             {:ok, title} <- normalize_text(title),
             {:ok, detail} <- normalize_text(detail) do
          [%{severity: severity_atom(severity), title: title, detail: detail}]
        else
          _ -> []
        end
      end)

    {:ok, concerns}
  end

  defp normalize_concerns(_concerns), do: :error

  defp severity_atom("info"), do: :info
  defp severity_atom("warning"), do: :warning
  defp severity_atom("critical"), do: :critical

  defp normalize_next_steps(next_steps) when is_list(next_steps) do
    {:ok, Enum.flat_map(next_steps, &normalize_text_list_item/1)}
  end

  defp normalize_next_steps(_next_steps), do: :error

  defp normalize_text_list_item(value) do
    case normalize_text(value) do
      {:ok, text} -> [text]
      :error -> []
    end
  end

  defp normalize_text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> :error
      text -> {:ok, text}
    end
  end

  defp normalize_text(_text), do: :error

  defp report_transactions(context) do
    Finance.list_transactions(
      date_from: context.period_start,
      date_to: DateTime.add(context.period_end, -1, :second),
      currency: context.currency,
      limit: 100
    )
  end

  defp expense_history(%{cadence: :weekly} = context) do
    Finance.expense_history(
      ending_on: context.period_end |> DateTime.add(-1, :second) |> DateTime.to_date(),
      months: @cost_history_months,
      currency: context.currency
    )
  end

  defp expense_history(_context), do: nil

  defp cost_history_prompt(%{cadence: :weekly} = context) do
    ending_on = context.period_end |> DateTime.add(-1, :second) |> DateTime.to_date() |> Date.to_iso8601()

    """
    Cost-history window: the three calendar months ending #{ending_on}.
    Call get_finance_expense_history before writing. Use its exact monthly totals rather than summing a limited transaction list.
    """
  end

  defp cost_history_prompt(_context), do: ""

  defp top_transactions(transactions) do
    transactions
    |> Enum.filter(&(match?(%Decimal{}, &1.amount_value) and &1.affects_runway))
    |> Enum.sort_by(& &1.amount_value, {:desc, Decimal})
    |> Enum.take(5)
    |> Enum.map(fn transaction ->
      %{
        label: transaction_label(transaction),
        direction: transaction.direction,
        amount_value: transaction.amount_value,
        amount_currency: transaction.amount_currency,
        occurred_at: Transaction.occurred_at(transaction)
      }
    end)
  end

  defp transaction_label(transaction) do
    transaction.counterparty_name || transaction.description || transaction.reference || "Unlabelled transaction"
  end

  defp fallback_summary(overview) do
    runway = format_runway(overview.runway_months)
    projected_runway = format_runway(overview.projected_runway_months)

    "Available cash is #{Amounts.format(overview.available_cash_value, overview.currency)}, with " <>
      "#{Amounts.format(overview.net_30d_value, overview.currency)} in net cash flow over the last 30 days. " <>
      "Monthly burn is #{Amounts.format(overview.monthly_burn_value, overview.currency)}, giving an estimated " <>
      "runway of #{runway}. Plan-adjusted runway is #{projected_runway}."
  end

  defp fallback_concerns(overview) do
    [
      runway_concern(overview),
      net_cash_flow_concern(overview),
      sync_freshness_concern(overview)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp runway_concern(%{runway_months: %Decimal{} = runway, currency: currency} = overview) do
    cond do
      Decimal.compare(runway, @critical_runway_months) == :lt ->
        %{
          severity: :critical,
          title: "Runway is below six months",
          detail:
            "Estimated runway is #{format_runway(runway)} with #{Amounts.format(overview.available_cash_value, currency)} available."
        }

      Decimal.compare(runway, @warning_runway_months) == :lt ->
        %{
          severity: :warning,
          title: "Runway is below twelve months",
          detail:
            "Estimated runway is #{format_runway(runway)} with #{Amounts.format(overview.available_cash_value, currency)} available."
        }

      true ->
        nil
    end
  end

  defp runway_concern(_overview), do: nil

  defp net_cash_flow_concern(%{net_30d_value: %Decimal{} = net_cash_flow, currency: currency}) do
    if Decimal.negative?(net_cash_flow) do
      %{
        severity: :warning,
        title: "Thirty-day net cash flow is negative",
        detail: "Net cash flow over the last 30 days is #{Amounts.format(net_cash_flow, currency)}."
      }
    end
  end

  defp net_cash_flow_concern(_overview), do: nil

  defp sync_freshness_concern(%{last_synced_at: %DateTime{} = last_synced_at}) do
    if DateTime.diff(DateTime.utc_now(), last_synced_at, :second) > @stale_sync_seconds do
      %{
        severity: :warning,
        title: "Finance data is stale",
        detail: "The latest successful source sync was #{DateTime.to_iso8601(last_synced_at)}."
      }
    end
  end

  defp sync_freshness_concern(%{last_synced_at: nil}) do
    %{
      severity: :warning,
      title: "Finance data has not synced",
      detail: "Atlas has no successful finance source sync timestamp."
    }
  end

  defp sync_freshness_concern(_overview), do: nil

  defp fallback_next_steps(overview) do
    [
      runway_next_step(overview.runway_months),
      net_cash_flow_next_step(overview.net_30d_value),
      sync_next_step(overview.last_synced_at)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp runway_next_step(%Decimal{} = runway) do
    if Decimal.compare(runway, @warning_runway_months) == :lt do
      "Review the largest recent outflows and committed renewals in Atlas."
    end
  end

  defp runway_next_step(_runway), do: nil

  defp net_cash_flow_next_step(%Decimal{} = net_cash_flow) do
    if Decimal.negative?(net_cash_flow) do
      "Confirm whether the largest recent debits are recurring or one-off costs."
    end
  end

  defp net_cash_flow_next_step(_net_cash_flow), do: nil

  defp sync_next_step(%DateTime{} = last_synced_at) do
    if DateTime.diff(DateTime.utc_now(), last_synced_at, :second) > @stale_sync_seconds do
      "Restore finance source synchronization before relying on this report."
    end
  end

  defp sync_next_step(nil), do: "Restore finance source synchronization before relying on this report."
  defp sync_next_step(_last_synced_at), do: nil

  defp fallback_headline(cadence, []), do: "#{cadence_label(cadence)} financial pulse"
  defp fallback_headline(cadence, _concerns), do: "#{cadence_label(cadence)} financial pulse needs attention"

  defp report_status([]), do: :ok
  defp report_status(_concerns), do: :attention

  defp format_runway(nil), do: "not available"

  defp format_runway(%Decimal{} = runway) do
    "#{runway |> Decimal.round(2) |> Decimal.to_string(:normal)} months"
  end

  defp list_opts(params) do
    [
      limit: page_size(params),
      date_from: parse_date_from(Map.get(params, "date_from")),
      date_to: parse_date_to(Map.get(params, "date_to")),
      direction: present(params, "direction"),
      status: present(params, "status"),
      kind: present(params, "kind"),
      currency: present(params, "currency"),
      query: present(params, "query")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp page_size(params) do
    case Map.get(params, "page_size") do
      value when is_integer(value) and value > 0 -> min(value, 100)
      _ -> @default_transaction_limit
    end
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

  defp parse_date(_value, _fallback_time), do: nil

  defp present(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp serialize_overview(overview) do
    %{
      currency: overview.currency,
      available_cash_value: decimal_to_string(overview.available_cash_value),
      total_balance_value: decimal_to_string(overview.total_balance_value),
      net_30d_value: decimal_to_string(overview.net_30d_value),
      monthly_burn_value: decimal_to_string(overview.monthly_burn_value),
      runway_months: decimal_to_string(overview.runway_months),
      projected_monthly_revenue_value: decimal_to_string(overview.projected_monthly_revenue_value),
      projected_arr_value: decimal_to_string(overview.projected_arr_value),
      projected_monthly_expenses_value: decimal_to_string(overview.projected_monthly_expenses_value),
      projected_net_burn_value: decimal_to_string(overview.projected_net_burn_value),
      projected_runway_months: decimal_to_string(overview.projected_runway_months),
      source_count: overview.source_count,
      account_count: overview.account_count,
      transaction_count_30d: overview.transaction_count_30d,
      last_synced_at: format_datetime(overview.last_synced_at)
    }
  end

  defp serialize_source(%Source{} = source) do
    %{
      provider: source.provider,
      config_key: source.config_key,
      name: source.name,
      last_synced_at: format_datetime(source.last_synced_at),
      last_successful_sync_at: format_datetime(source.last_successful_sync_at),
      last_error: source.last_error
    }
  end

  defp serialize_expense_history(%{currency: currency, months: months}) do
    %{
      currency: currency,
      months:
        Enum.map(months, fn month ->
          %{
            date_from: Date.to_iso8601(month.period.date_from),
            date_to: Date.to_iso8601(month.period.date_to),
            partial: month.period.partial?,
            total_amount_value: decimal_to_string(month.total_amount_value),
            included_transaction_count: month.included_transaction_count,
            matching_debit_transaction_count: month.matching_debit_transaction_count,
            complete: month.complete?,
            categories:
              Enum.map(month.categories, fn category ->
                %{
                  name: category.name,
                  transaction_count: category.transaction_count,
                  total_amount_value: decimal_to_string(category.total_amount_value)
                }
              end),
            exclusions: month.exclusions
          }
        end)
    }
  end

  defp serialize_transaction(%Transaction{} = transaction) do
    %{
      id: transaction.id,
      occurred_at: format_datetime(Transaction.occurred_at(transaction)),
      provider: transaction.provider,
      status: transaction.status,
      direction: transaction.direction,
      kind: transaction.kind,
      counterparty_name: transaction.counterparty_name,
      description: transaction.description,
      reference: transaction.reference,
      amount_value: decimal_to_string(transaction.amount_value),
      amount_currency: transaction.amount_currency,
      affects_runway: transaction.affects_runway,
      category: serialize_category(transaction.category),
      account: %{
        name: transaction.account.name,
        currency: transaction.account.currency,
        provider: transaction.account.provider,
        source_name: transaction.account.source.name
      }
    }
  end

  defp serialize_category(nil), do: nil

  defp serialize_category(category) do
    %{
      name: category.name,
      slug: category.slug,
      direction: category.direction
    }
  end

  defp format_date(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()
  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(value), do: Decimal.to_string(value)

  defp periods(:daily, %DateTime{} = now) do
    period_end = now |> DateTime.to_date() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    period_start = DateTime.add(period_end, -1, :day)
    comparison_period_start = DateTime.add(period_start, -30, :day)

    {period_start, period_end, comparison_period_start}
  end

  defp periods(:weekly, %DateTime{} = now) do
    current_week_start_date =
      now
      |> DateTime.to_date()
      |> monday_of_week()

    current_week_start = DateTime.new!(current_week_start_date, ~T[00:00:00], "Etc/UTC")
    period_start = DateTime.add(current_week_start, -7 * 24 * 60 * 60, :second)
    previous_period_start = DateTime.add(current_week_start, -14 * 24 * 60 * 60, :second)

    {period_start, current_week_start, previous_period_start}
  end

  defp cadence_label(:daily), do: "Daily"
  defp cadence_label(:weekly), do: "Weekly"

  defp cadence(context), do: Map.get(context, :cadence, :weekly)

  defp monday_of_week(%Date{} = date) do
    Date.add(date, -(Date.day_of_week(date) - 1))
  end
end
