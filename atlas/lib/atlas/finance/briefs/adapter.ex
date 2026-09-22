defmodule Atlas.Finance.Briefs.Adapter do
  alias Atlas.Finance
  alias Atlas.Finance.Agents.WeeklySummaryAgent
  alias Atlas.Finance.MonthlyRecap
  alias Atlas.Finance.Transaction

  require Logger

  def candidate_items("daily", period) do
    financial_pulse("daily", period)
  end

  def candidate_items("weekly", period) do
    financial_pulse("weekly", period)
  end

  def candidate_items("monthly", period) do
    report = MonthlyRecap.build(period)

    {:ok,
     %{
       summary: report["intro"],
       report: report,
       items: [],
       generation_mode: "deterministic"
     }}
  end

  defp financial_pulse(cadence, period) do
    context = WeeklySummaryAgent.context(cadence: cadence_atom(cadence), now: period.end_at)

    {report, generation_mode, generated_by_agent, fallback_reason} =
      case WeeklySummaryAgent.summarize(context) do
        {:ok, readout} ->
          {WeeklySummaryAgent.build_report(context, readout), "agent", "weekly_summary_agent", nil}

        {:error, reason} ->
          Logger.warning("Falling back to deterministic #{cadence} finance pulse: #{inspect(reason)}")
          {WeeklySummaryAgent.fallback(context), "deterministic_fallback", nil, reason}
      end

    transactions =
      Finance.list_transactions(
        date_from: context.period_start,
        date_to: DateTime.add(context.period_end, -1, :second),
        currency: context.currency,
        limit: 10
      )

    {:ok,
     %{
       summary: report.readout.summary,
       report: pulse_report(report, generation_mode),
       items: finance_pulse_items(report.readout, transactions, context),
       generation_mode: generation_mode,
       generated_by_agent: generated_by_agent,
       fallback_reason: fallback_reason
     }}
  end

  # Keep the narrative separate from action items: materiality and the attention
  # budget must not remove the explanation or repeat it as a task list in Slack.
  defp pulse_report(report, generation_mode) do
    readout = report.readout

    %{
      "kind" => "finance_pulse",
      "headline" => readout.headline,
      "intro" => readout.summary,
      "generation_mode" => generation_mode,
      "drivers" => Enum.map(Map.get(readout, :drivers, []), &report_finding/1),
      "concerns" => Enum.map(readout.concerns, &report_finding/1),
      "next_steps" => readout.next_steps
    }
  end

  defp report_finding(finding), do: %{"title" => finding.title, "detail" => finding.detail}

  defp cadence_atom("daily"), do: :daily
  defp cadence_atom("weekly"), do: :weekly

  # A daily pulse is an informational check-in. It keeps material risks in the
  # narrative rather than repeatedly creating the same action queue every day.
  # The weekly pulse remains the review surface for finance follow-ups.
  defp finance_pulse_items(_readout, _transactions, %{cadence: :daily}), do: []

  defp finance_pulse_items(readout, transactions, context) do
    evidence = Enum.map(transactions, &transaction_evidence/1)

    concern_items =
      Enum.map(readout.concerns, fn concern ->
        severity = to_string(concern.severity)

        %{
          domain: "finance",
          kind: "risk",
          title: concern.title,
          detail: concern.detail,
          severity: severity,
          sensitivity: "restricted",
          materiality_score: severity_score(severity),
          suggested_action: List.first(readout.next_steps),
          completion_condition: "Leadership has reviewed the risk and recorded an owner or resolution.",
          fingerprint: "finance:weekly:#{fingerprint(concern.title)}",
          source_path: "/commercial/finance",
          due_at: DateTime.add(context.period_end, 7, :day),
          evidence: evidence
        }
      end)

    follow_ups =
      if concern_items == [] do
        []
      else
        readout.next_steps
        |> Enum.with_index()
        |> Enum.map(fn {step, index} ->
          %{
            domain: "finance",
            kind: "follow_up",
            title: short_title(step),
            detail: step,
            severity: "info",
            sensitivity: "restricted",
            materiality_score: Decimal.new("0.60"),
            suggested_action: step,
            completion_condition: "The follow-up is completed and its result is recorded.",
            fingerprint: "finance:weekly:follow_up:#{index}:#{fingerprint(step)}",
            source_path: "/commercial/finance",
            due_at: DateTime.add(context.period_end, 7, :day),
            evidence: evidence
          }
        end)
      end

    concern_items ++ follow_ups
  end

  defp transaction_evidence(%Transaction{} = transaction) do
    label = transaction.counterparty_name || transaction.description || transaction.reference || "Transaction"

    %{
      record_type: "finance_transaction",
      record_id: transaction.id,
      source_class: "observed",
      observation: "#{label}: #{transaction.amount_value} #{transaction.amount_currency}"
    }
  end

  defp severity_score("critical"), do: Decimal.new("0.95")
  defp severity_score("warning"), do: Decimal.new("0.80")
  defp severity_score(_severity), do: Decimal.new("0.55")

  defp short_title(text) do
    text
    |> String.split(~r/[.!?]\s/u, parts: 2)
    |> List.first()
    |> String.slice(0, 120)
  end

  defp fingerprint(text) do
    :crypto.hash(:sha256, String.downcase(text)) |> Base.encode16(case: :lower) |> String.slice(0, 20)
  end
end
