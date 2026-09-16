defmodule Atlas.Finance.Workers.PostWeeklySummaryTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Briefs
  alias Atlas.Finance.Agents.WeeklySummaryAgent
  alias Atlas.Finance.Workers.PostWeeklySummary
  alias Atlas.Slack.API
  alias Atlas.Slack.Channel

  # `slack_channels.channel_id` is unique across the table, so the channel this
  # module syncs has to be its own. Tests inside a module run one at a time, so a
  # module-wide id cannot contend with itself the way a suite-wide one does.
  @slack_channel_id "C-WEEKLY-SUMMARY"

  setup :verify_on_exit!

  test "generates and posts the shared weekly leadership brief" do
    insert_subscription!()
    context = context_fixture()
    readout = %{headline: "Weekly financial pulse", summary: "Stable.", concerns: [], next_steps: []}
    report = Map.put(context, :readout, readout)

    expect(WeeklySummaryAgent, :context, fn [cadence: :weekly, now: _now] -> context end)
    expect(WeeklySummaryAgent, :summarize, fn ^context -> {:ok, readout} end)
    expect(WeeklySummaryAgent, :build_report, fn ^context, ^readout -> report end)
    expect_post(:ok)

    assert :ok = PostWeeklySummary.perform(%Oban.Job{})
    assert {_briefs, %{total_count: 1}} = Briefs.list_briefs(cadence: "weekly")
  end

  test "posts a deterministic weekly fallback" do
    insert_subscription!()
    context = context_fixture()

    report =
      Map.put(context, :readout, %{
        headline: "Weekly fallback",
        summary: "No material finance concerns.",
        concerns: [],
        next_steps: []
      })

    expect(WeeklySummaryAgent, :context, fn [cadence: :weekly, now: _now] -> context end)
    expect(WeeklySummaryAgent, :summarize, fn ^context -> {:error, :language_model_credit_limit} end)
    expect(WeeklySummaryAgent, :fallback, fn ^context -> report end)
    expect_post(:ok, "Weekly fallback")

    assert :ok = PostWeeklySummary.perform(%Oban.Job{})
  end

  test "returns delivery errors so the job can retry" do
    insert_subscription!()
    context = context_fixture()
    readout = %{headline: "Weekly financial pulse", summary: "Stable.", concerns: [], next_steps: []}
    report = Map.put(context, :readout, readout)

    expect(WeeklySummaryAgent, :context, fn [cadence: :weekly, now: _now] -> context end)
    expect(WeeklySummaryAgent, :summarize, fn ^context -> {:ok, readout} end)
    expect(WeeklySummaryAgent, :build_report, fn ^context, ^readout -> report end)
    expect_post({:error, :slack_down})

    assert {:error, :slack_down} = PostWeeklySummary.perform(%Oban.Job{})
  end

  defp expect_post(result, headline \\ "Weekly financial pulse") do
    expect(API, :find_message_by_metadata, fn :company, @slack_channel_id, "atlas_brief", _brief_id ->
      {:ok, nil}
    end)

    expect(API, :post_message, fn :company, @slack_channel_id, text, blocks, opts ->
      assert text =~ headline
      assert hd(blocks)["text"]["text"] == headline
      assert is_list(blocks)
      assert is_binary(opts[:client_msg_id])

      case result do
        :ok -> {:ok, %{"channel" => @slack_channel_id, "ts" => "1.0"}}
        error -> error
      end
    end)
  end

  defp insert_subscription! do
    %Channel{slack_app: :company}
    |> Channel.changeset(%{channel_id: @slack_channel_id, channel_name: "leadership"})
    |> Atlas.Repo.insert!()

    {:ok, subscription} =
      Briefs.upsert_subscription(%{
        label: "Leadership weekly",
        # Fixed by `PostWeeklySummary.perform/1`, which generates for the
        # "leadership" audience by name. No other module writes this pair, and a
        # single shared value can only serialize, never deadlock.
        audience_key: "leadership",
        cadence: "weekly",
        domains: ["finance"],
        slack_app: "company",
        slack_channel_id: @slack_channel_id,
        max_sensitivity: "restricted",
        attention_budget: 8,
        enabled: true
      })

    subscription
  end

  defp context_fixture do
    %{
      currency: "EUR",
      period_start: ~U[2026-07-13 00:00:00Z],
      period_end: ~U[2026-07-20 00:00:00Z],
      previous_period_start: ~U[2026-07-06 00:00:00Z],
      previous_period_end: ~U[2026-07-13 00:00:00Z]
    }
  end
end
