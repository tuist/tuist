defmodule Atlas.Briefs.Composer do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Calibration
  alias Atlas.Briefs.Materiality
  alias Atlas.Briefs.Sensitivity
  alias Atlas.Briefs.Subscription
  alias Atlas.Briefs.Suppression
  alias Atlas.Evidence
  alias Atlas.Finance.Briefs.Adapter
  alias Atlas.Repo

  @adapters %{
    "finance" => Adapter,
    "outreach" => Atlas.Outreach.Briefs.Adapter,
    "product" => Atlas.Product.Briefs.Adapter,
    "company" => Atlas.Coordination.Briefs.Adapter
  }

  @severity_rank %{"info" => 1, "warning" => 2, "critical" => 3}

  def compose(%Subscription{} = subscription, opts \\ []) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:second)
    period = Keyword.get(opts, :period) || period(subscription.cadence, now)

    case existing_brief(subscription.id, subscription.cadence, period.start_at) do
      nil -> build_brief(subscription, period, now)
      brief -> {:ok, preload_brief(brief)}
    end
  end

  def period("daily", now) do
    end_at = now |> DateTime.to_date() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    %{start_at: DateTime.add(end_at, -1, :day), end_at: end_at}
  end

  def period("weekly", now) do
    date = DateTime.to_date(now)
    monday = Date.add(date, 1 - Date.day_of_week(date))
    end_at = DateTime.new!(monday, ~T[00:00:00], "Etc/UTC")
    %{start_at: DateTime.add(end_at, -7, :day), end_at: end_at}
  end

  def period("monthly", now) do
    month_start = now |> DateTime.to_date() |> Date.beginning_of_month()
    next_month_start = month_start |> Date.end_of_month() |> Date.add(1)

    %{
      start_at: DateTime.new!(month_start, ~T[00:00:00], "Etc/UTC"),
      end_at: DateTime.new!(next_month_start, ~T[00:00:00], "Etc/UTC")
    }
  end

  defp build_brief(subscription, period, now) do
    with {:ok, ceiling} <- Sensitivity.ceiling(subscription) do
      domain_results =
        subscription.domains
        |> Enum.map(&adapter_result(&1, subscription.cadence, period))
        |> Enum.reject(&is_nil/1)

      suppressed = active_suppressions(subscription.id, now)
      calibration = Calibration.factors()

      items =
        domain_results
        |> Enum.flat_map(& &1.items)
        |> Enum.map(&Calibration.apply(&1, calibration))
        |> Enum.flat_map(&inherit_evidence_sensitivity/1)
        |> Enum.uniq_by(& &1.fingerprint)
        |> Enum.filter(&candidate_allowed?(&1, subscription.cadence, ceiling, suppressed))
        |> select_with_domain_coverage(subscription.domains, subscription.attention_budget)

      report = report(domain_results)
      status = if items == [] and report == %{}, do: "immaterial", else: "material"
      generation = generation_metadata(domain_results)

      Repo.transaction(fn ->
        brief =
          %Brief{brief_subscription_id: subscription.id}
          |> Brief.changeset(%{
            cadence: subscription.cadence,
            period_start: period.start_at,
            period_end: period.end_at,
            status: status,
            headline: headline(subscription, report),
            summary: combined_summary(domain_results),
            report: report,
            attention_budget: subscription.attention_budget,
            sensitivity: Sensitivity.max(Enum.map(items, & &1.sensitivity)),
            generated_by_agent: generation.generated_by_agent,
            generation_mode: generation.generation_mode
          })
          |> Repo.insert!()

        inserted_items =
          items
          |> Enum.with_index()
          |> Enum.map(fn {candidate, position} -> insert_item!(brief, candidate, position) end)

        brief = %{brief | items: inserted_items, subscription: subscription}
        audit_brief(brief, generation)
        preload_brief(brief)
      end)
    end
  rescue
    error in [Ecto.InvalidChangesetError, Ecto.ConstraintError] ->
      case existing_brief(subscription.id, subscription.cadence, period.start_at) do
        nil -> reraise error, __STACKTRACE__
        brief -> {:ok, preload_brief(brief)}
      end
  end

  defp adapter_result(domain, cadence, period) do
    with module when not is_nil(module) <- Map.get(@adapters, domain),
         {:ok, result} <- module.candidate_items(cadence, period) do
      Map.put(result, :domain, domain)
    else
      _error -> nil
    end
  end

  defp candidate_allowed?(candidate, cadence, ceiling, suppressed) do
    Materiality.material?(candidate, cadence) and
      Sensitivity.permits?(ceiling, candidate.sensitivity) and
      not suppressed?(candidate, suppressed)
  end

  # A suppression silences a record as it stood when its item was closed. When
  # the same record later escalates to a higher severity that is new
  # information, so it reaches the brief before the cooldown expires.
  defp suppressed?(candidate, suppressed) do
    case Map.fetch(suppressed, {candidate.domain, candidate.fingerprint}) do
      :error -> false
      {:ok, nil} -> true
      {:ok, severity} -> severity_rank(candidate.severity) <= severity_rank(severity)
    end
  end

  defp severity_rank(severity), do: Map.get(@severity_rank, severity, 0)

  defp inherit_evidence_sensitivity(candidate) do
    case Evidence.sensitivity_for(Map.get(candidate, :evidence, []), candidate.sensitivity) do
      {:ok, sensitivity} -> [Map.put(candidate, :sensitivity, sensitivity)]
      {:error, _reason} -> []
    end
  end

  defp active_suppressions(subscription_id, now) do
    Suppression
    |> where(
      [suppression],
      suppression.brief_subscription_id == ^subscription_id and
        (is_nil(suppression.suppressed_until) or suppression.suppressed_until > ^now)
    )
    |> select([suppression], {{suppression.domain, suppression.fingerprint}, suppression.severity})
    |> Repo.all()
    |> Map.new()
  end

  defp insert_item!(brief, candidate, position) do
    evidence = Map.get(candidate, :evidence, [])

    item =
      %BriefItem{brief_id: brief.id}
      |> BriefItem.changeset(
        candidate
        |> Map.delete(:evidence)
        |> Map.put(:position, position)
      )
      |> Repo.insert!()

    case Evidence.link_all("brief_item", item.id, evidence) do
      {:ok, _links} -> item
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp existing_brief(subscription_id, cadence, period_start) do
    Repo.get_by(Brief,
      brief_subscription_id: subscription_id,
      cadence: cadence,
      period_start: period_start
    )
  end

  defp preload_brief(brief) do
    Repo.preload(brief, [:subscription, items: [:owner, :resolved_by, :usefulness_by]], force: true)
  end

  defp rank(candidate) do
    severity = Map.fetch!(@severity_rank, candidate.severity)
    score = candidate.materiality_score |> Decimal.mult(1000) |> Decimal.round(0) |> Decimal.to_integer()
    {severity, score}
  end

  defp select_with_domain_coverage(candidates, domains, budget) do
    ranked = Enum.sort_by(candidates, &rank/1, :desc)

    reserved =
      domains
      |> Enum.flat_map(fn domain ->
        case Enum.find(ranked, &(&1.domain == domain)) do
          nil -> []
          candidate -> [candidate]
        end
      end)
      |> Enum.sort_by(&rank/1, :desc)
      |> Enum.take(budget)

    reserved_fingerprints = MapSet.new(reserved, &{&1.domain, &1.fingerprint})

    remaining =
      Enum.reject(ranked, fn candidate ->
        MapSet.member?(reserved_fingerprints, {candidate.domain, candidate.fingerprint})
      end)

    (reserved ++ Enum.take(remaining, budget - length(reserved)))
    |> Enum.sort_by(&rank/1, :desc)
  end

  defp headline(%Subscription{domains: ["finance"]}, %{"kind" => "finance_pulse", "headline" => headline}), do: headline

  defp headline(%Subscription{cadence: "daily"}, _report), do: "Daily financial pulse"
  defp headline(%Subscription{cadence: "weekly"}, _report), do: "Weekly financial pulse"

  defp headline(%Subscription{cadence: "monthly"}, report) do
    Map.get(report, "headline", "Month-end financial recap")
  end

  defp report(results) do
    results
    |> Enum.map(&Map.get(&1, :report, %{}))
    |> Enum.find(%{}, &(Map.get(&1, "kind") in ["monthly_finance_recap", "finance_pulse"]))
  end

  defp combined_summary([%{domain: "finance", summary: summary}]), do: summary

  defp combined_summary(results) do
    results
    |> Enum.map_join("\n", fn result -> "#{String.capitalize(result.domain)}: #{result.summary}" end)
  end

  defp generation_metadata(results) do
    modes = results |> Enum.map(& &1.generation_mode) |> Enum.uniq()

    generation_mode =
      cond do
        "agent" in modes -> "agent"
        "deterministic_fallback" in modes -> "deterministic_fallback"
        true -> "deterministic"
      end

    agents =
      results
      |> Enum.map(& &1.generated_by_agent)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join(",")

    %{
      generation_mode: generation_mode,
      generated_by_agent: empty_to_nil(agents),
      fallback_reasons: fallback_reasons(results)
    }
  end

  # Keeps the reason a domain fell back to deterministic output in the audit
  # trail, so an operator can tell a quiet week from a language-model outage.
  defp fallback_reasons(results) do
    results
    |> Enum.flat_map(fn result ->
      case Map.get(result, :fallback_reason) do
        nil -> []
        reason -> [{result.domain, inspect(reason)}]
      end
    end)
    |> Map.new()
  end

  defp audit_brief(brief, generation) do
    Audit.record(
      "brief.generated",
      %{
        target_type: "brief",
        target_id: brief.id,
        target_label: brief.headline,
        metadata: %{
          "audience" => brief.subscription.audience_key,
          "cadence" => brief.cadence,
          "domains" => brief.subscription.domains,
          "item_count" => length(brief.items),
          "status" => brief.status,
          "generation_mode" => generation.generation_mode,
          "generated_by_agent" => generation.generated_by_agent,
          "fallback_reasons" => generation.fallback_reasons,
          "report_kind" => Map.get(brief.report, "kind"),
          "dashboard_path" => report_dashboard_path(brief.report)
        }
      },
      interface: "worker"
    )
  end

  defp report_dashboard_path(%{"kind" => kind}) when kind in ["monthly_finance_recap", "finance_pulse"], do: "/commercial/finance"
  defp report_dashboard_path(_report), do: nil

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
