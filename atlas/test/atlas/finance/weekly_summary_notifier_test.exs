defmodule Atlas.Finance.WeeklySummaryNotifierTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Finance.WeeklySummaryNotifier

  setup :verify_on_exit!

  test "builds attention blocks with concerns and largest expenses" do
    summary = summary_fixture()

    blocks = WeeklySummaryNotifier.build_blocks(summary)

    assert hd(blocks)["text"]["text"] == "Weekly finance summary needs attention"
    assert Enum.any?(blocks, &(&1["type"] == "section" and inspect(&1) =~ "SaaS spend drove the increase"))
    assert Enum.any?(blocks, &(&1["type"] == "section" and inspect(&1) =~ "Available cash"))
    assert Enum.any?(blocks, &(&1["type"] == "section" and inspect(&1) =~ "Grafana Labs"))
    assert Enum.any?(blocks, &(&1["type"] == "section" and inspect(&1) =~ "Review SaaS renewals"))
    refute inspect(blocks) =~ "—"
  end

  test "posts to the configured Slack channel with the injected poster" do
    test_pid = self()

    poster = fn app_key, channel, text, blocks ->
      send(test_pid, {:posted, app_key, channel, text, blocks})
      {:ok, %{"ok" => true}}
    end

    assert :ok =
             WeeklySummaryNotifier.maybe_post(summary_fixture(),
               finance_config: [weekly_summary_slack_channel_id: "C_FINANCE_READOUT"],
               poster: poster
             )

    assert_received {:posted, :company, "C_FINANCE_READOUT", text, blocks}
    assert text =~ "Weekly finance summary"
    assert is_list(blocks)
  end

  test "returns an error when no Slack channel is configured" do
    assert {:error, :missing_weekly_summary_slack_channel_id} =
             WeeklySummaryNotifier.maybe_post(summary_fixture(), finance_config: [])
  end

  defp summary_fixture do
    %{
      status: :attention,
      currency: "EUR",
      period_start: ~U[2026-05-18 00:00:00Z],
      period_end: ~U[2026-05-25 00:00:00Z],
      transaction_count: 2,
      overview: %{
        currency: "EUR",
        available_cash_value: Decimal.new("294870.97"),
        net_30d_value: Decimal.new("-35834.25"),
        monthly_burn_value: Decimal.new("36048.38"),
        runway_months: Decimal.new("8.18"),
        projected_monthly_revenue_value: Decimal.new("25000.00"),
        projected_runway_months: Decimal.new("9.59")
      },
      top_transactions: [
        %{
          label: "Grafana Labs",
          direction: "debit",
          amount_value: Decimal.new("3993.03"),
          amount_currency: "EUR",
          occurred_at: ~U[2026-05-21 10:00:00Z]
        }
      ],
      readout: %{
        headline: "Weekly finance summary needs attention",
        summary: "SaaS spend drove the increase this week.",
        concerns: [
          %{
            severity: :warning,
            title: "Costs increased",
            detail: "Expenses rose from EUR 100.00 to EUR 600.00."
          }
        ],
        next_steps: ["Review SaaS renewals before the next leadership meeting."]
      },
      previous_period_start: ~U[2026-05-11 00:00:00Z],
      previous_period_end: ~U[2026-05-18 00:00:00Z]
    }
  end
end
