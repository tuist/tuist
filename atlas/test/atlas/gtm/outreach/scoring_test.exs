defmodule Atlas.GTM.Outreach.ScoringTest do
  use ExUnit.Case, async: true

  alias Atlas.GTM.Outreach.Scoring
  alias Atlas.GTM.Signal

  test "scores recent build, scale, and pain evidence with a readable rationale" do
    recent = DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)

    signals = [
      %Signal{
        title: "Acme improves iOS CI with Tuist and Project.swift",
        excerpt: "Xcode build-times were slow, so the mobile platform team added cache-backed Swift modules.",
        matched_terms: [
          "iOS",
          "Swift",
          "Xcode",
          "Project.swift",
          "Tuist",
          "monorepo",
          "platform",
          "CI",
          "slow",
          "cache"
        ],
        signal_kind: "engineering_blog",
        confidence: 95,
        observed_at: recent
      },
      %Signal{
        title: "Bundle-size and flaky-test gates for CI/CD",
        excerpt: "Developer productivity work covers app-size reliability and modularization.",
        matched_terms: ["bundle-size", "flaky", "CI/CD", "modules", "developer productivity"],
        signal_kind: "developer_productivity",
        confidence: 87,
        observed_at: DateTime.add(recent, -1, :day)
      }
    ]

    assert %{
             score: 94,
             score_breakdown: %{
               "build_system" => 5,
               "scale" => 5,
               "pain" => 5,
               "recency" => 5,
               "evidence" => 2,
               "source_confidence" => 5
             },
             latest_signal_at: ^recent
           } = result = Scoring.score(signals)

    assert result.rationale =~ "Strong build-system evidence"
    assert result.rationale =~ "2 evidence items captured"
    assert result.signal_summary =~ "2 signals"
    assert result.signal_summary =~ "engineering_blog"
    assert result.signal_summary =~ "developer_productivity"
  end

  test "keeps weak stale evidence low and summarizes missing metadata" do
    old = DateTime.utc_now() |> DateTime.add(-220, :day) |> DateTime.truncate(:second)

    assert %{
             score: score,
             score_breakdown: %{
               "build_system" => 0,
               "scale" => 0,
               "pain" => 0,
               "recency" => 1,
               "evidence" => 1,
               "source_confidence" => 1
             },
             signal_summary: "1 signals captured.",
             latest_signal_at: ^old
           } =
             Scoring.score([
               %Signal{
                 title: "Generic engineering post",
                 excerpt: "Team update.",
                 matched_terms: [],
                 signal_kind: nil,
                 confidence: 30,
                 observed_at: old
               }
             ])

    assert score < 10
  end
end
