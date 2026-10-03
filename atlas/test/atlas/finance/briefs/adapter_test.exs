defmodule Atlas.Finance.Briefs.AdapterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance
  alias Atlas.Finance.Agents.WeeklySummaryAgent
  alias Atlas.Finance.Briefs.Adapter
  alias Atlas.Finance.Transaction

  setup :verify_on_exit!

  test "the weekly summary carries the standing cash position" do
    stub(WeeklySummaryAgent, :summarize, fn _context -> {:error, :llm_not_configured} end)
    stub(Finance, :overview, fn -> overview_fixture() end)

    stub(Finance, :list_transactions, fn _opts ->
      [
        %Transaction{
          direction: "debit",
          counterparty_name: "Grafana Labs",
          amount_value: Decimal.new("3993.03"),
          amount_currency: "EUR",
          affects_runway: true,
          settled_at: ~U[2026-05-21 10:00:00Z]
        }
      ]
    end)

    stub(Finance, :expense_history, fn _opts -> expense_history_fixture() end)

    assert {:ok, result} =
             Adapter.candidate_items("weekly", %{
               start_at: ~U[2026-05-18 00:00:00Z],
               end_at: ~U[2026-05-25 00:00:00Z]
             })

    assert result.summary =~ "Available cash is EUR 294,870.97"
    assert result.summary =~ "Monthly burn is EUR 36,048.38"
    assert result.summary =~ "8.18 months"
    assert result.summary =~ "Plan-adjusted runway is 9.59 months"
    assert result.report["kind"] == "finance_pulse"
    assert result.report["generation_mode"] == "deterministic_fallback"
    assert result.report["intro"] == result.summary
    refute result.summary =~ " | "
    refute result.summary =~ "Largest cash movements"
  end

  test "the daily pulse uses the previous day and carries the standing cash position" do
    stub(WeeklySummaryAgent, :summarize, fn _context -> {:error, :llm_not_configured} end)
    stub(Finance, :overview, fn -> overview_fixture() end)
    stub(Finance, :list_transactions, fn _opts -> [] end)

    assert {:ok, result} =
             Adapter.candidate_items("daily", %{
               start_at: ~U[2026-05-24 00:00:00Z],
               end_at: ~U[2026-05-25 00:00:00Z]
             })

    assert result.summary =~ "Available cash is EUR 294,870.97"
    assert result.summary =~ "8.18 months"
    assert result.items == []
  end

  test "a language-model failure is recorded as the reason the brief fell back" do
    stub(WeeklySummaryAgent, :summarize, fn _context -> {:error, :language_model_credit_limit} end)
    stub(Finance, :overview, fn -> overview_fixture() end)
    stub(Finance, :list_transactions, fn _opts -> [] end)
    stub(Finance, :expense_history, fn _opts -> expense_history_fixture() end)

    assert {:ok, result} =
             Adapter.candidate_items("weekly", %{
               start_at: ~U[2026-05-18 00:00:00Z],
               end_at: ~U[2026-05-25 00:00:00Z]
             })

    assert result.generation_mode == "deterministic_fallback"
    assert result.fallback_reason == :language_model_credit_limit
  end

  test "keeps agent analysis without appending a deterministic metrics dump" do
    readout = %{
      headline: "Hardware purchases drove this week's spending",
      summary: "Cash remains sufficient for eight months at the current burn rate.",
      drivers: [%{title: "Hardware purchases", detail: "Grafana was the largest recorded debit."}],
      concerns: [],
      next_steps: ["Confirm whether the purchase is a one-off."]
    }

    stub(WeeklySummaryAgent, :summarize, fn _context -> {:ok, readout} end)
    stub(Finance, :overview, fn -> overview_fixture() end)
    stub(Finance, :list_transactions, fn _opts -> [] end)
    stub(Finance, :expense_history, fn _opts -> expense_history_fixture() end)

    assert {:ok, result} =
             Adapter.candidate_items("weekly", %{
               start_at: ~U[2026-05-18 00:00:00Z],
               end_at: ~U[2026-05-25 00:00:00Z]
             })

    assert result.summary == readout.summary
    assert result.report["headline"] == readout.headline

    assert result.report["drivers"] == [
             %{"title" => "Hardware purchases", "detail" => "Grafana was the largest recorded debit."}
           ]

    assert result.report["next_steps"] == readout.next_steps
    assert result.items == []
    assert result.generation_mode == "agent"
  end

  defp overview_fixture do
    %{
      currency: "EUR",
      available_cash_value: Decimal.new("294870.97"),
      net_30d_value: Decimal.new("-35834.25"),
      monthly_burn_value: Decimal.new("36048.38"),
      projected_monthly_revenue_value: Decimal.new("41200.00"),
      runway_months: Decimal.new("8.18"),
      projected_runway_months: Decimal.new("9.59"),
      last_synced_at: ~U[2026-05-25 08:00:00Z]
    }
  end

  defp expense_history_fixture do
    %{
      currency: "EUR",
      months: [
        %{
          period: %{date_from: ~D[2026-03-01], date_to: ~D[2026-03-31], partial?: false},
          total_amount_value: Decimal.new("31000.00"),
          complete?: true
        },
        %{
          period: %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], partial?: false},
          total_amount_value: Decimal.new("34000.00"),
          complete?: true
        },
        %{
          period: %{date_from: ~D[2026-05-01], date_to: ~D[2026-05-24], partial?: true},
          total_amount_value: Decimal.new("28000.00"),
          complete?: true
        }
      ]
    }
  end
end
