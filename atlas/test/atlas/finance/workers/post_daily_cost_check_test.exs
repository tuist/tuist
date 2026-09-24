defmodule Atlas.Finance.Workers.PostDailyCostCheckTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Briefs
  alias Atlas.Finance
  alias Atlas.Finance.Agents.WeeklySummaryAgent
  alias Atlas.Finance.Workers.PostDailyCostCheck
  alias Atlas.Slack.API
  alias Atlas.Slack.Channel

  # `slack_channels.channel_id` is unique across the table, so the channel this
  # module syncs has to be its own. Tests inside a module run one at a time, so a
  # module-wide id cannot contend with itself the way a suite-wide one does.
  @slack_channel_id "C-DAILY-COST-CHECK"

  setup :verify_on_exit!

  test "posts a daily financial pulse even when no action item crosses the attention threshold" do
    insert_subscription!()
    context = context_fixture()

    readout = %{
      headline: "Daily financial pulse",
      summary: "No material financial concerns.",
      concerns: [],
      next_steps: []
    }

    expect(WeeklySummaryAgent, :context, fn [cadence: :daily, now: _now] -> context end)
    expect(WeeklySummaryAgent, :summarize, fn ^context -> {:ok, readout} end)
    stub_finance()
    expect_reconciliation()

    expect(API, :post_message, fn :company, @slack_channel_id, text, blocks, _opts ->
      assert text =~ "Daily financial pulse"
      assert is_list(blocks)
      {:ok, %{"channel" => @slack_channel_id, "ts" => "1.0"}}
    end)

    assert :ok = PostDailyCostCheck.perform(%Oban.Job{})
    assert {_briefs, %{total_count: 1}} = Briefs.list_briefs(cadence: "daily")
  end

  test "uses the deterministic fallback and posts the daily financial pulse" do
    insert_subscription!()
    context = context_fixture()

    report = %{
      overview: overview_fixture(),
      readout: %{
        headline: "Daily financial pulse needs attention",
        summary: "Cloud costs increased.",
        concerns: [%{severity: :warning, title: "Cloud costs increased", detail: "Cloud costs increased materially."}],
        next_steps: ["Review the cloud bill."]
      }
    }

    expect(WeeklySummaryAgent, :context, fn [cadence: :daily, now: _now] -> context end)
    expect(WeeklySummaryAgent, :summarize, fn ^context -> {:error, :language_model_credit_limit} end)
    expect(WeeklySummaryAgent, :fallback, fn ^context -> report end)
    stub_finance()
    expect_reconciliation()

    expect(API, :post_message, fn :company, @slack_channel_id, text, blocks, opts ->
      assert text =~ "Daily financial pulse"
      assert is_list(blocks)
      assert is_binary(opts[:client_msg_id])
      {:ok, %{"channel" => @slack_channel_id, "ts" => "1.0"}}
    end)

    assert :ok = PostDailyCostCheck.perform(%Oban.Job{})
  end

  test "returns delivery errors so the job can retry" do
    insert_subscription!()
    context = context_fixture()

    readout = %{
      headline: "Daily financial pulse needs attention",
      summary: "Cloud costs increased.",
      concerns: [%{severity: :warning, title: "Cloud costs increased", detail: "Cloud costs increased materially."}],
      next_steps: ["Review the cloud bill."]
    }

    expect(WeeklySummaryAgent, :context, fn [cadence: :daily, now: _now] -> context end)
    expect(WeeklySummaryAgent, :summarize, fn ^context -> {:ok, readout} end)
    stub_finance()
    expect_reconciliation()
    expect(API, :post_message, fn :company, @slack_channel_id, _text, _blocks, _opts -> {:error, :slack_down} end)

    assert {:error, :slack_down} = PostDailyCostCheck.perform(%Oban.Job{})
  end

  defp insert_subscription! do
    %Channel{slack_app: :company}
    |> Channel.changeset(%{channel_id: @slack_channel_id, channel_name: "leadership"})
    |> Atlas.Repo.insert!()

    {:ok, subscription} =
      Briefs.upsert_subscription(%{
        label: "Leadership daily",
        # Fixed by `PostDailyCostCheck.perform/1`, which generates for the
        # "leadership" audience by name. No other module writes this pair, and a
        # single shared value can only serialize, never deadlock.
        audience_key: "leadership",
        cadence: "daily",
        domains: ["finance"],
        slack_app: "company",
        slack_channel_id: @slack_channel_id,
        max_sensitivity: "restricted",
        attention_budget: 8,
        enabled: true
      })

    subscription
  end

  defp expect_reconciliation do
    expect(API, :find_message_by_metadata, fn :company, @slack_channel_id, "atlas_brief", _brief_id ->
      {:ok, nil}
    end)
  end

  defp stub_finance do
    stub(Finance, :overview, fn -> overview_fixture() end)
    stub(Finance, :list_transactions, fn _opts -> [] end)
  end

  defp overview_fixture do
    %{
      currency: "EUR",
      available_cash_value: Decimal.new("294870.97"),
      net_30d_value: Decimal.new("-35834.25"),
      monthly_burn_value: Decimal.new("36048.38"),
      projected_monthly_revenue_value: Decimal.new("41200.00"),
      runway_months: Decimal.new("8.18"),
      projected_runway_months: Decimal.new("9.59")
    }
  end

  defp context_fixture do
    %{
      cadence: :daily,
      currency: "EUR",
      period_start: ~U[2026-07-20 00:00:00Z],
      period_end: ~U[2026-07-21 00:00:00Z],
      previous_period_start: ~U[2026-06-20 00:00:00Z],
      previous_period_end: ~U[2026-07-20 00:00:00Z]
    }
  end
end
