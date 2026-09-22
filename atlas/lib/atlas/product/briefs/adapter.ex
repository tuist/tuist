defmodule Atlas.Product.Briefs.Adapter do
  import Ecto.Query

  alias Atlas.Product.Trace
  alias Atlas.Repo

  @stale_pull_request_days 7

  def candidate_items(cadence, period) when cadence in ["daily", "weekly"] do
    stale = stale_pull_requests(period.end_at)
    shipped = shipped_changes(period)

    {:ok,
     %{
       summary:
         "#{length(shipped)} release-related changes shipped and #{length(stale)} open pull requests exceeded the review window.",
       items: stale_items(stale, period) ++ shipped_items(shipped, period),
       generation_mode: "deterministic",
       generated_by_agent: nil
     }}
  end

  defp stale_pull_requests(now) do
    before = DateTime.add(now, -@stale_pull_request_days, :day)

    from(trace in Trace,
      as: :opened_trace,
      where: trace.kind == "pull_request_opened" and trace.occurred_at <= ^before,
      where:
        not exists(
          from resolution in Trace,
            where:
              resolution.github_repository_id == parent_as(:opened_trace).github_repository_id and
                resolution.number == parent_as(:opened_trace).number and
                resolution.kind in ["pull_request_merged", "pull_request_closed"]
        ),
      order_by: [asc: trace.occurred_at]
    )
    |> Repo.all()
  end

  defp shipped_changes(period) do
    Trace
    |> where(
      [trace],
      trace.kind == "pull_request_merged" and trace.occurred_at >= ^period.start_at and
        trace.occurred_at < ^period.end_at
    )
    |> order_by([trace], desc: trace.occurred_at)
    |> Repo.all()
    |> Enum.filter(&release_related?/1)
  end

  defp stale_items(traces, period) do
    Enum.map(traces, fn trace ->
      %{
        domain: "product",
        kind: "expectation_missed",
        title: "#{trace.repository_full_name} ##{trace.number} is waiting",
        detail:
          "#{trace.title} has remained open for more than #{@stale_pull_request_days} days without a merge or close event.",
        severity: "warning",
        sensitivity: trace.sensitivity,
        materiality_score: Decimal.new("0.72"),
        suggested_action: "Assign an owner to close, merge, or explicitly defer the pull request.",
        completion_condition: "The pull request is merged, closed, or explicitly deferred.",
        fingerprint: "product:stale_pull_request:#{trace.github_repository_id}:#{trace.number}",
        source_type: "product_trace",
        source_id: trace.id,
        source_path: trace.url,
        due_at: DateTime.add(period.end_at, 7, :day),
        evidence: [trace_evidence(trace)]
      }
    end)
  end

  defp shipped_items([], _period), do: []

  defp shipped_items(traces, period) do
    detail =
      traces
      |> Enum.take(5)
      |> Enum.map_join("; ", &"#{&1.repository_full_name} ##{&1.number}: #{&1.title}")

    source_trace = List.first(traces)

    [
      %{
        domain: "product",
        kind: "change",
        title: "Release-related product changes shipped",
        detail: detail,
        severity: "info",
        sensitivity: most_sensitive(traces),
        materiality_score: Decimal.new("0.55"),
        suggested_action: "Confirm whether customer-facing release communication is complete.",
        completion_condition: "The shipped changes are acknowledged and any required communication is published.",
        fingerprint: "product:release_changes:#{period.start_at |> DateTime.to_date()}",
        source_path: source_trace.url,
        evidence: Enum.map(traces, &trace_evidence/1)
      }
    ]
  end

  defp trace_evidence(trace) do
    %{
      record_type: "product_trace",
      record_id: trace.id,
      source_class: "observed",
      observation: "#{trace.repository_full_name} ##{trace.number}: #{trace.title}"
    }
  end

  defp release_related?(trace) do
    Enum.any?(trace.labels, fn label ->
      normalized = String.downcase(label)
      String.contains?(normalized, "release") or String.contains?(normalized, "changelog")
    end)
  end

  defp most_sensitive(traces) do
    if Enum.any?(traces, &(&1.sensitivity == "restricted")), do: "restricted", else: "internal"
  end
end
