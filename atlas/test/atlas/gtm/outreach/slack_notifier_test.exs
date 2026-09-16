defmodule Atlas.GTM.Outreach.SlackNotifierTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.GTM
  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.Outreach.SlackNotifier
  alias Atlas.Repo
  alias Atlas.Slack.API

  setup :verify_on_exit!

  defp insert_opportunity! do
    {:ok, signal} =
      GTM.record_gtm_signal(%{
        company_name: "Acme Mobile",
        company_key: "domain:acme.example",
        domain: "acme.example",
        source: "brave",
        source_ref: "https://acme.example/blog/ios-ci",
        source_url: "https://acme.example/blog/ios-ci",
        title: "Acme scales iOS CI with Tuist and Xcode",
        excerpt: "iOS Swift Xcode monorepo platform mobile CI modules slow cache flaky reliability.",
        matched_terms: ["iOS", "Swift", "Xcode", "Tuist", "monorepo", "platform", "mobile", "CI", "slow", "cache"],
        signal_kind: "engineering_blog",
        confidence: 95,
        observed_at: ~U[2026-06-01 12:00:00Z],
        metadata: %{}
      })

    GTM.get_gtm_opportunity(signal.opportunity_id)
  end

  test "builds action buttons for a GTM opportunity" do
    opportunity = insert_opportunity!()

    blocks = SlackNotifier.build_blocks(opportunity)
    actions = blocks |> Enum.filter(&(&1["type"] == "actions")) |> Enum.flat_map(& &1["elements"])

    assert Enum.any?(actions, &(&1["text"]["text"] == "Find leaders"))
    assert Enum.any?(actions, &(&1["action_id"] == SlackNotifier.action_id("qualify")))
    assert Enum.any?(actions, &(&1["action_id"] == SlackNotifier.action_id("convert")))
    assert Enum.any?(actions, &(&1["action_id"] == SlackNotifier.action_id("reject")))
    assert Enum.any?(actions, &(&1["url"] =~ "/gtm/outreach"))
  end

  test "posts the notification to the configured Slack channel" do
    opportunity = insert_opportunity!()

    expect(API, :post_message, fn :company, "C_MARKETING", text, blocks ->
      assert text =~ "Acme Mobile"
      assert is_list(blocks)
      {:ok, %{"ok" => true, "channel" => "C_MARKETING", "ts" => "1717400000.000100"}}
    end)

    assert {:ok,
            %{
              slack_notification_channel_id: "C_MARKETING",
              slack_notification_thread_ts: "1717400000.000100"
            }} = SlackNotifier.notify(opportunity, slack_channel_id: "C_MARKETING")
  end

  test "updates an existing notification" do
    opportunity =
      insert_opportunity!()
      |> Opportunity.slack_notification_changeset(%{
        slack_notification_channel_id: "C_MARKETING",
        slack_notification_thread_ts: "1717400000.000100",
        slack_notification_posted_at: ~U[2026-06-01 12:00:00Z]
      })
      |> Repo.update!()
      |> then(&GTM.get_gtm_opportunity(&1.id))

    expect(API, :update_message, fn :company, "C_MARKETING", "1717400000.000100", text, blocks ->
      assert text =~ "Acme Mobile"
      assert is_list(blocks)
      {:ok, %{"ok" => true}}
    end)

    assert {:ok,
            %{
              slack_notification_channel_id: "C_MARKETING",
              slack_notification_thread_ts: "1717400000.000100"
            }} = SlackNotifier.notify(opportunity)
  end
end
