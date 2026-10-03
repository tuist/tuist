defmodule Atlas.Briefs.CalibrationTest do
  use Atlas.DataCase, async: true

  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Calibration
  alias Atlas.Briefs.Subscription

  test "repeated not useful feedback lowers similar future items after enough samples" do
    brief = insert_brief!()

    for index <- 0..4 do
      insert_rated_item!(brief, index, "not_useful")
    end

    factors = Calibration.factors()

    candidate = %{
      domain: "product",
      kind: "change",
      materiality_score: Decimal.new("0.80")
    }

    adjusted = Calibration.apply(candidate, factors)
    assert Decimal.equal?(adjusted.materiality_score, Decimal.new("0.400"))
  end

  test "small samples remain neutral" do
    brief = insert_brief!()
    insert_rated_item!(brief, 0, "not_useful")

    adjusted =
      Calibration.apply(
        %{domain: "product", kind: "change", materiality_score: Decimal.new("0.80")},
        Calibration.factors()
      )

    assert Decimal.equal?(adjusted.materiality_score, Decimal.new("0.80"))
  end

  defp insert_brief! do
    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        label: "Calibration",
        audience_key: "calibration-#{System.unique_integer([:positive])}",
        cadence: "weekly",
        domains: ["product"],
        slack_app: "company",
        slack_channel_id: "C-CALIBRATION",
        max_sensitivity: "internal",
        attention_budget: 8,
        enabled: true
      })
      |> Repo.insert!()

    %Brief{brief_subscription_id: subscription.id}
    |> Brief.changeset(%{
      cadence: "weekly",
      period_start: ~U[2026-07-13 00:00:00Z],
      period_end: ~U[2026-07-20 00:00:00Z],
      status: "material",
      attention_budget: 8,
      sensitivity: "internal",
      generation_mode: "deterministic"
    })
    |> Repo.insert!()
  end

  defp insert_rated_item!(brief, index, usefulness) do
    %BriefItem{brief_id: brief.id}
    |> BriefItem.changeset(%{
      domain: "product",
      kind: "change",
      title: "Release change #{index}",
      detail: "A release-related change shipped.",
      severity: "info",
      sensitivity: "internal",
      materiality_score: Decimal.new("0.60"),
      fingerprint: "product:change:#{index}",
      position: index,
      status: "open",
      usefulness: usefulness,
      usefulness_at: ~U[2026-07-20 10:00:00Z]
    })
    |> Repo.insert!()
  end
end
