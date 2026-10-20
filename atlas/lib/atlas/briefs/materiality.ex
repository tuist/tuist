defmodule Atlas.Briefs.Materiality do
  @moduledoc false

  @daily_threshold Decimal.new("0.65")
  @weekly_threshold Decimal.new("0.50")

  def material?(%{severity: "critical"}, _cadence), do: true
  def material?(%{materiality_score: nil}, _cadence), do: false

  def material?(%{materiality_score: score}, "daily") do
    Decimal.compare(decimal(score), @daily_threshold) in [:eq, :gt]
  end

  def material?(%{materiality_score: score}, "weekly") do
    Decimal.compare(decimal(score), @weekly_threshold) in [:eq, :gt]
  end

  def material?(_item, _cadence), do: false

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(to_string(value))
end
