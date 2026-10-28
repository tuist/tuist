defmodule Atlas.Assets.BookValueTest do
  use ExUnit.Case, async: true

  alias Atlas.Assets.Asset
  alias Atlas.Assets.BookValue

  describe "months_elapsed/2" do
    test "counts zero on the placement day" do
      assert BookValue.months_elapsed(~D[2026-03-20], ~D[2026-03-20]) == 0
    end

    test "counts zero the day before the first anniversary" do
      assert BookValue.months_elapsed(~D[2026-03-20], ~D[2026-04-19]) == 0
    end

    test "counts one on the first anniversary" do
      assert BookValue.months_elapsed(~D[2026-03-20], ~D[2026-04-20]) == 1
    end

    test "clamps a short target month to its last valid day" do
      assert BookValue.months_elapsed(~D[2026-01-31], ~D[2026-02-27]) == 0
      assert BookValue.months_elapsed(~D[2026-01-31], ~D[2026-02-28]) == 1
    end

    test "handles anniversary skipping through short months" do
      assert BookValue.months_elapsed(~D[2026-01-31], ~D[2026-03-30]) == 1
      assert BookValue.months_elapsed(~D[2026-01-31], ~D[2026-03-31]) == 2
    end

    test "returns a negative count before the placement date" do
      assert BookValue.months_elapsed(~D[2026-03-20], ~D[2026-03-19]) == -1
    end
  end

  describe "at/2 with the depreciable treatment" do
    setup do
      asset = %Asset{
        placed_in_service_on: ~D[2026-03-20],
        acquisition_cost: Decimal.new("3600.00"),
        acquisition_currency: "EUR",
        salvage_value: Decimal.new("0"),
        useful_life_months: 36,
        valuation_treatment: "depreciable"
      }

      %{asset: asset}
    end

    test "returns full acquisition cost before service", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2026-03-19])
      assert Decimal.equal?(value, Decimal.new("3600.00"))
    end

    test "returns full acquisition cost on the placement day", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2026-03-20])
      assert Decimal.equal?(value, Decimal.new("3600.00"))
    end

    test "returns full cost the day before the first anniversary", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2026-04-19])
      assert Decimal.equal?(value, Decimal.new("3600.00"))
    end

    test "depreciates one thirty-sixth by the first anniversary", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2026-04-20])
      assert Decimal.equal?(value, Decimal.new("3500.00"))
    end

    test "returns one monthly step before end of life", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2029-03-19])
      assert Decimal.equal?(value, Decimal.new("100.00"))
    end

    test "true-ups to zero at end of life", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2029-03-20])
      assert Decimal.equal?(value, Decimal.new("0.00"))
    end

    test "remains at zero past end of life", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2029-04-15])
      assert Decimal.equal?(value, Decimal.new("0.00"))
    end

    test "true-ups exactly to salvage_value at end of life when set" do
      asset = %Asset{
        placed_in_service_on: ~D[2026-03-20],
        acquisition_cost: Decimal.new("3600.00"),
        acquisition_currency: "EUR",
        salvage_value: Decimal.new("300.00"),
        useful_life_months: 36,
        valuation_treatment: "depreciable"
      }

      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2029-03-20])
      assert Decimal.equal?(value, Decimal.new("300.00"))
    end

    test "handles a placement on January 31 across a non-leap February" do
      asset = %Asset{
        placed_in_service_on: ~D[2026-01-31],
        acquisition_cost: Decimal.new("2400.00"),
        acquisition_currency: "EUR",
        salvage_value: Decimal.new("0"),
        useful_life_months: 24,
        valuation_treatment: "depreciable"
      }

      assert {:ok, jan_end, "EUR"} = BookValue.at(asset, on: ~D[2026-02-27])
      assert Decimal.equal?(jan_end, Decimal.new("2400.00"))

      assert {:ok, feb_end, "EUR"} = BookValue.at(asset, on: ~D[2026-02-28])
      assert Decimal.equal?(feb_end, Decimal.new("2300.00"))

      assert {:ok, mar_end_pre_anniversary, "EUR"} = BookValue.at(asset, on: ~D[2026-03-30])
      assert Decimal.equal?(mar_end_pre_anniversary, Decimal.new("2300.00"))

      assert {:ok, mar_end_anniversary, "EUR"} = BookValue.at(asset, on: ~D[2026-03-31])
      assert Decimal.equal?(mar_end_anniversary, Decimal.new("2200.00"))
    end

    test "returns pre-service full cost when placed_in_service_on is nil" do
      asset = %Asset{
        placed_in_service_on: nil,
        acquisition_cost: Decimal.new("1500.00"),
        acquisition_currency: "EUR",
        salvage_value: Decimal.new("0"),
        useful_life_months: 36,
        valuation_treatment: "depreciable"
      }

      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2027-01-01])
      assert Decimal.equal?(value, Decimal.new("1500.00"))
    end
  end

  describe "at/2 with the fully_expensed treatment" do
    setup do
      asset = %Asset{
        placed_in_service_on: ~D[2026-03-20],
        acquisition_cost: Decimal.new("200.00"),
        acquisition_currency: "EUR",
        salvage_value: Decimal.new("0"),
        useful_life_months: 24,
        valuation_treatment: "fully_expensed"
      }

      %{asset: asset}
    end

    test "returns full acquisition cost before service", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2026-03-19])
      assert Decimal.equal?(value, Decimal.new("200.00"))
    end

    test "returns salvage value from placement onward", %{asset: asset} do
      assert {:ok, value, "EUR"} = BookValue.at(asset, on: ~D[2026-03-20])
      assert Decimal.equal?(value, Decimal.new("0"))
    end
  end

  describe "at/2 with the unknown treatment" do
    test "returns a missing valuation error" do
      asset = %Asset{
        valuation_treatment: "unknown",
        acquisition_currency: "EUR"
      }

      assert BookValue.at(asset, on: ~D[2026-06-01]) == {:error, :missing_valuation}
    end
  end
end
