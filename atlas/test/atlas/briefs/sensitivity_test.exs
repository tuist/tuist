defmodule Atlas.Briefs.SensitivityTest do
  use Atlas.DataCase, async: true

  alias Atlas.Briefs.Sensitivity
  alias Atlas.Briefs.Subscription
  alias Atlas.Slack.Channel

  test "externally shared channels only accept public brief content" do
    channel =
      %Channel{slack_app: :company}
      |> Channel.changeset(%{
        channel_id: "C-EXTERNAL",
        channel_name: "shared-customer-channel",
        is_shared: true,
        is_ext_shared: true
      })
      |> Repo.insert!()

    restricted = subscription(channel.channel_id, "restricted")
    public = subscription(channel.channel_id, "public")

    assert {:ok, "public"} = Sensitivity.ceiling(restricted)
    assert {:error, :subscription_exceeds_channel_sensitivity} = Sensitivity.validate_subscription(restricted)
    assert :ok = Sensitivity.validate_subscription(public)
    assert Sensitivity.permits?("public", "public")
    refute Sensitivity.permits?("public", "internal")
  end

  test "channels Atlas has not synced are an error rather than a silent public ceiling" do
    restricted = subscription("C-NOT-SYNCED", "restricted")
    public = subscription("C-NOT-SYNCED", "public")

    assert {:error, :slack_channel_not_synced} = Sensitivity.ceiling(restricted)
    assert {:error, :slack_channel_not_synced} = Sensitivity.validate_subscription(restricted)
    assert {:error, :slack_channel_not_synced} = Sensitivity.validate_subscription(public)
  end

  defp subscription(channel_id, maximum) do
    %Subscription{
      label: "Shared brief",
      audience_key: "shared",
      cadence: "daily",
      domains: ["accounts"],
      slack_app: "company",
      slack_channel_id: channel_id,
      max_sensitivity: maximum,
      attention_budget: 8,
      enabled: true
    }
  end
end
