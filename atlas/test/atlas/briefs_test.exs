defmodule Atlas.BriefsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Briefs
  alias Atlas.Briefs.Config
  alias Atlas.Briefs.Subscription
  alias Atlas.Slack.API
  alias Atlas.Slack.Channel

  test "tracks the leadership channel and creates weekly and monthly financial brief subscriptions on a migrated database" do
    stub(Config, :leadership_slack_channel_id, fn -> "C-LEADERSHIP" end)

    expect(API, :get_channel_info, fn :company, "C-LEADERSHIP" ->
      {:ok,
       %{
         slack_app: :company,
         slack_channel_id: "C-LEADERSHIP",
         name: "leadership",
         is_shared: false,
         is_ext_shared: false,
         is_member: true,
         is_private: true
       }}
    end)

    assert {:ok, subscriptions} = Briefs.ensure_default_subscriptions()
    assert Enum.map(subscriptions, & &1.cadence) == ["weekly", "monthly"]

    channel = Repo.get_by!(Channel, slack_app: :company, channel_id: "C-LEADERSHIP")
    assert channel.channel_name == "leadership"
    assert channel.is_ext_shared == false

    weekly = Briefs.get_subscription("leadership", "weekly")
    assert weekly.slack_channel_id == "C-LEADERSHIP"
    assert weekly.domains == ["finance"]
    assert Repo.get_by!(Activity, action: "brief_subscription.created", target_id: weekly.id)

    channel_activity = Repo.get_by!(Activity, action: "slack_channel.tracked", target_id: channel.id)
    assert channel_activity.interface == "worker"
  end

  test "leaves an existing subscription as the operator left it" do
    stub(Config, :leadership_slack_channel_id, fn -> "C-LEADERSHIP" end)

    stub(API, :get_channel_info, fn :company, "C-LEADERSHIP" ->
      {:ok,
       %{
         slack_app: :company,
         slack_channel_id: "C-LEADERSHIP",
         name: "leadership",
         is_shared: false,
         is_ext_shared: false,
         is_member: true,
         is_private: true
       }}
    end)

    assert {:ok, _created} = Briefs.ensure_default_subscriptions()

    weekly = Briefs.get_subscription("leadership", "weekly")

    {:ok, _disabled} =
      weekly
      |> Subscription.changeset(%{enabled: false, attention_budget: 3})
      |> Repo.update()

    assert {:ok, _ensured} = Briefs.ensure_default_subscriptions()

    unchanged = Repo.get!(Subscription, weekly.id)
    refute unchanged.enabled
    assert unchanged.attention_budget == 3

    assert Repo.aggregate(from(subscription in Subscription, where: subscription.audience_key == "leadership"), :count) ==
             2
  end

  test "reports a missing channel rather than creating an undeliverable subscription" do
    stub(Config, :leadership_slack_channel_id, fn -> nil end)

    assert {:error, :leadership_slack_channel_not_configured} = Briefs.ensure_default_subscriptions()
    assert Briefs.list_subscriptions() == []
  end

  test "does not create subscriptions when the configured channel cannot be inspected" do
    stub(Config, :leadership_slack_channel_id, fn -> "C-LEADERSHIP" end)
    stub(API, :get_channel_info, fn :company, "C-LEADERSHIP" -> {:error, "channel_not_found"} end)

    assert {:error, "channel_not_found"} = Briefs.ensure_default_subscriptions()
    assert Briefs.list_subscriptions() == []
  end
end
