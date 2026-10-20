defmodule AtlasWeb.FinanceLive.QueryParamsTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.FinanceLive.QueryParams

  describe "normalize_finance_params/1" do
    test "copies legacy query and filter params into Noora filter params" do
      params = QueryParams.normalize_finance_params(%{"query" => " payroll ", "provider" => "qonto"})

      assert params["search"] == "payroll"
      assert params["filter_provider_op"] == "=="
      assert params["filter_provider_val"] == "qonto"
    end

    test "does not overwrite current search or filter params" do
      params =
        QueryParams.normalize_finance_params(%{
          "search" => "current",
          "query" => "legacy",
          "provider" => "qonto",
          "filter_provider_val" => "mercury"
        })

      assert params["search"] == "current"
      assert params["filter_provider_val"] == "mercury"
      refute Map.has_key?(params, "filter_provider_op")
    end
  end

  describe "transactions_date_picker_params/1" do
    test "parses a valid custom range" do
      params = %{
        "transactions-date-range" => "custom",
        "transactions-start-date" => "2026-05-01",
        "transactions-end-date" => "2026-05-31"
      }

      assert %{
               preset: "custom",
               period: {~U[2026-05-01 00:00:00Z], ~U[2026-05-31 23:59:59Z]}
             } = QueryParams.transactions_date_picker_params(params)
    end

    test "drops invalid custom ranges" do
      assert %{preset: nil, period: nil} =
               QueryParams.transactions_date_picker_params(%{
                 "transactions-date-range" => "custom",
                 "transactions-start-date" => "wat",
                 "transactions-end-date" => "2026-05-31"
               })
    end
  end

  describe "transaction_filters/4" do
    test "returns compact finance query options" do
      filters = [
        %{id: "provider", value: " qonto "},
        %{id: "direction", value: "debit"}
      ]

      assert [
               page: 3,
               page_size: 25,
               provider: "qonto",
               direction: "debit",
               date_from: ~U[2026-05-01 00:00:00Z],
               date_to: ~U[2026-05-31 23:59:59Z],
               query: "payroll"
             ] =
               QueryParams.transaction_filters(
                 " payroll ",
                 filters,
                 {~U[2026-05-01 00:00:00Z], ~U[2026-05-31 23:59:59Z]},
                 3
               )
    end
  end
end
