defmodule Atlas.Assets.BookValue do
  @moduledoc """
  Pure straight-line depreciation math for `Atlas.Assets.Asset`.

  The month convention is single-formula anniversary counting: an
  anniversary of the placed-in-service date lands on the same day of the
  month, clamped to the last valid day of a shorter month, so
  January 31 -> February 28 counts as one full month elapsed on the 28th
  of February in non-leap years. The convention is documented in
  `docs/hardware-inventory-proposal.md`.

  All arithmetic is `Decimal`. No floats. Results are rounded to two
  decimal places (half-up) to match the underlying column scale, with a
  final-period true-up that guarantees the fully depreciated result equals
  `acquisition_cost - salvage_value` exactly.

  The function ignores fleet eligibility. `Atlas.Assets.fleet_eligible?/2`
  gates inclusion in aggregate fleet reports.
  """

  alias Atlas.Assets.Asset

  @doc """
  Estimated book value of `asset` on `date`.

  Returns one of:
  * `{:ok, %Decimal{}, currency}` for depreciable and fully-expensed assets
    whose acquisition cost is known.
  * `{:error, :missing_valuation}` when `valuation_treatment` is `:unknown`.

  Behaviour:
  * Pre-service (no `placed_in_service_on`, or `date` before it) returns
    the full acquisition cost, matching the "not yet depreciating" view.
  * `fully_expensed` treatment returns `salvage_value` from the placed-in-service
    date onward.
  * `depreciable` treatment applies the anniversary-counting formula with a
    final-period true-up.
  """
  def at(%Asset{} = asset, on: %Date{} = date) do
    case asset.valuation_treatment do
      "unknown" ->
        {:error, :missing_valuation}

      "fully_expensed" ->
        {:ok, fully_expensed_value(asset, date), asset.acquisition_currency}

      "depreciable" ->
        {:ok, depreciable_value(asset, date), asset.acquisition_currency}
    end
  end

  @doc """
  Full elapsed anniversary months between `start` and `date`.

  See the module docs for the anniversary-counting convention.
  """
  def months_elapsed(%Date{} = start, %Date{} = date) do
    raw = (date.year - start.year) * 12 + (date.month - start.month)

    days_in_target = Date.days_in_month(date)
    reference_day = min(start.day, days_in_target)

    day_adjust = if date.day < reference_day, do: -1, else: 0

    raw + day_adjust
  end

  defp fully_expensed_value(%Asset{placed_in_service_on: nil} = asset, _date) do
    asset.acquisition_cost
  end

  defp fully_expensed_value(%Asset{placed_in_service_on: placed_on} = asset, date) do
    if Date.before?(date, placed_on), do: asset.acquisition_cost, else: asset.salvage_value
  end

  defp depreciable_value(%Asset{placed_in_service_on: nil} = asset, _date) do
    asset.acquisition_cost
  end

  defp depreciable_value(%Asset{placed_in_service_on: placed_on} = asset, date) do
    if Date.before?(date, placed_on) do
      asset.acquisition_cost
    else
      compute_depreciable(asset, date)
    end
  end

  defp compute_depreciable(%Asset{} = asset, date) do
    life = asset.useful_life_months
    elapsed = months_elapsed(asset.placed_in_service_on, date) |> clamp(0, life)

    depreciable = Decimal.sub(asset.acquisition_cost, asset.salvage_value)

    accumulated =
      cond do
        elapsed <= 0 ->
          Decimal.new(0)

        elapsed >= life ->
          depreciable

        true ->
          depreciable
          |> Decimal.mult(Decimal.new(elapsed))
          |> Decimal.div(Decimal.new(life))
          |> Decimal.round(2, :half_up)
      end

    asset.acquisition_cost
    |> Decimal.sub(accumulated)
    |> Decimal.round(2, :half_up)
  end

  defp clamp(value, lower, upper) do
    value
    |> max(lower)
    |> min(upper)
  end
end
