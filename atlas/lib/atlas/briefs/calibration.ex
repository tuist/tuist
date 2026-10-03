defmodule Atlas.Briefs.Calibration do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Briefs.BriefItem
  alias Atlas.Repo

  @minimum_sample_size 5
  @neutral_factor Decimal.new("1.0")
  @minimum_factor Decimal.new("0.5")

  def factors do
    BriefItem
    |> where([item], not is_nil(item.usefulness))
    |> group_by([item], [item.domain, item.kind, item.usefulness])
    |> select([item], {item.domain, item.kind, item.usefulness, count(item.id)})
    |> Repo.all()
    |> Enum.group_by(fn {domain, kind, _usefulness, _count} -> {domain, kind} end)
    |> Map.new(fn {key, rows} -> {key, factor(rows)} end)
  end

  def apply(candidate, factors) do
    factor = Map.get(factors, {candidate.domain, candidate.kind}, @neutral_factor)
    Map.update!(candidate, :materiality_score, &Decimal.mult(decimal(&1), factor))
  end

  defp factor(rows) do
    useful = count(rows, "useful")
    total = useful + count(rows, "not_useful")

    if total < @minimum_sample_size do
      @neutral_factor
    else
      usefulness_rate = Decimal.div(Decimal.new(useful), Decimal.new(total))
      Decimal.add(@minimum_factor, Decimal.mult(@minimum_factor, usefulness_rate))
    end
  end

  defp count(rows, usefulness) do
    Enum.find_value(rows, 0, fn
      {_domain, _kind, ^usefulness, count} -> count
      _row -> nil
    end)
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(to_string(value))
end
