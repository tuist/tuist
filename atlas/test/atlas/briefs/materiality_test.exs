defmodule Atlas.Briefs.MaterialityTest do
  use ExUnit.Case, async: true

  alias Atlas.Briefs.Materiality

  test "daily briefs require a higher materiality score than weekly briefs" do
    candidate = %{severity: "info", materiality_score: Decimal.new("0.55")}

    refute Materiality.material?(candidate, "daily")
    assert Materiality.material?(candidate, "weekly")
  end

  test "critical items always cross the attention threshold" do
    assert Materiality.material?(%{severity: "critical", materiality_score: Decimal.new("0.10")}, "daily")
  end
end
