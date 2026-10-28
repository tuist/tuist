defmodule Atlas.GTM.Outreach.Scoring do
  @moduledoc false

  @build_terms ~w(ios swift xcode xcodebuild swiftpm package.swift project.swift tuist fastfile fastlane xcodegen)
  @scale_terms ~w(monorepo platform mobile infrastructure productivity ci/cd ci modules modularization)
  @pain_terms ~w(slow speed cache caching flaky reliability migration migrated build-times build_time build-times app-size bundle-size)

  def score(signals) when is_list(signals) do
    latest_signal_at = latest_signal_at(signals)
    build_system = score_terms(signals, @build_terms)
    scale = score_terms(signals, @scale_terms)
    pain = score_terms(signals, @pain_terms)
    recency = recency_score(latest_signal_at)
    evidence = min(length(signals), 5)
    source_confidence = source_confidence_score(signals)

    score =
      (build_system / 5 * 32 + scale / 5 * 18 + pain / 5 * 18 + recency / 5 * 12 + evidence / 5 * 10 +
         source_confidence / 5 * 10)
      |> round()
      |> min(100)

    %{
      score: score,
      score_breakdown: %{
        "build_system" => build_system,
        "scale" => scale,
        "pain" => pain,
        "recency" => recency,
        "evidence" => evidence,
        "source_confidence" => source_confidence
      },
      rationale: rationale(build_system, scale, pain, evidence, source_confidence),
      signal_summary: signal_summary(signals),
      latest_signal_at: latest_signal_at
    }
  end

  defp score_terms(signals, terms) do
    text = combined_text(signals)

    terms
    |> Enum.count(&String.contains?(text, &1))
    |> min(5)
  end

  defp source_confidence_score([]), do: 0

  defp source_confidence_score(signals) do
    average =
      signals
      |> Enum.map(&(&1.confidence || 0))
      |> Enum.sum()
      |> div(max(length(signals), 1))

    cond do
      average >= 90 -> 5
      average >= 75 -> 4
      average >= 60 -> 3
      average >= 40 -> 2
      average > 0 -> 1
      true -> 0
    end
  end

  defp recency_score(nil), do: 0

  defp recency_score(%DateTime{} = datetime) do
    days = DateTime.diff(DateTime.utc_now(), datetime, :day)

    cond do
      days <= 7 -> 5
      days <= 30 -> 4
      days <= 90 -> 3
      days <= 180 -> 2
      true -> 1
    end
  end

  defp latest_signal_at(signals) do
    signals
    |> Enum.map(& &1.observed_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix/1, fn -> nil end)
  end

  defp rationale(build_system, scale, pain, evidence, source_confidence) do
    [
      if(build_system >= 3, do: "Strong build-system evidence", else: "Some build-system evidence"),
      if(scale >= 3, do: "scale or platform-engineering language is present", else: "limited scale language"),
      if(pain >= 2, do: "possible build or CI pain is visible", else: "pain is not explicit"),
      "#{evidence} evidence #{pluralize(evidence, "item")} captured",
      "average source confidence #{source_confidence}/5"
    ]
    |> Enum.join(". ")
    |> Kernel.<>(".")
  end

  defp signal_summary(signals) do
    kinds =
      signals
      |> Enum.map(& &1.signal_kind)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join(", ")

    terms =
      signals
      |> Enum.flat_map(&(&1.matched_terms || []))
      |> Enum.uniq()
      |> Enum.take(8)
      |> Enum.join(", ")

    cond do
      kinds != "" and terms != "" -> "#{length(signals)} signals: #{kinds}. Matched: #{terms}."
      kinds != "" -> "#{length(signals)} signals: #{kinds}."
      true -> "#{length(signals)} signals captured."
    end
  end

  defp combined_text(signals) do
    signals
    |> Enum.flat_map(fn signal ->
      [signal.title, signal.excerpt, signal.signal_kind | signal.matched_terms || []]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp pluralize(1, singular), do: singular
  defp pluralize(_count, singular), do: singular <> "s"
end
