defmodule Atlas.GTM.Workers.PostAudienceMemberNotificationTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.GTM.AudienceMemberNotifier
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Workers.PostAudienceMemberNotification

  setup :verify_on_exit!

  setup do
    {:ok, audience} = Audiences.create_audience(%{name: "Product users"})

    {:ok, subscriber} =
      Audiences.create_subscriber(
        %{email: "member@example.com", source: "posthog"},
        nil,
        automations: false
      )

    membership =
      %AudienceMembership{audience_id: audience.id, subscriber_id: subscriber.id}
      |> AudienceMembership.changeset(%{status: "subscribed"})
      |> Repo.insert!()

    %{audience: audience, subscriber: subscriber, membership: membership}
  end

  test "posts the audience member and records the delivery", %{
    audience: audience,
    subscriber: subscriber,
    membership: membership
  } do
    notification_id = Ecto.UUID.generate()

    expect(AudienceMemberNotifier, :announce, fn announced_audience, announced_subscriber, announced_id ->
      assert announced_audience.id == audience.id
      assert announced_subscriber.id == subscriber.id
      assert announced_id == notification_id
      {:ok, %{"ts" => "1717400000.000100"}}
    end)

    assert :ok = perform(membership.id, notification_id)

    activity = Repo.get_by!(Activity, action: "gtm_audience.subscriber_announced", target_id: audience.id)
    assert activity.interface == "worker"
    assert activity.metadata["subscriber_id"] == subscriber.id
    assert activity.metadata["subscriber_email"] == subscriber.email
    assert activity.metadata["slack_channel_id"] == "C0AGV3YU8ET"
    assert activity.metadata["slack_message_ts"] == "1717400000.000100"
    assert activity.metadata["dashboard_path"] == "/email/audiences/#{audience.id}"
  end

  test "returns Slack errors so the job can retry", %{membership: membership} do
    expect(AudienceMemberNotifier, :announce, fn _audience, _subscriber, _notification_id ->
      {:error, "slack_down"}
    end)

    assert {:error, "slack_down"} = perform(membership.id, Ecto.UUID.generate())
  end

  test "cancels when the membership no longer exists" do
    assert {:cancel, :membership_not_found} = perform(Ecto.UUID.generate(), Ecto.UUID.generate())
  end

  test "cancels when the member is no longer subscribed", %{membership: membership} do
    membership
    |> AudienceMembership.changeset(%{status: "unsubscribed"})
    |> Repo.update!()

    assert {:cancel, :membership_not_subscribed} = perform(membership.id, Ecto.UUID.generate())
  end

  defp perform(membership_id, notification_id) do
    PostAudienceMemberNotification.perform(%Oban.Job{
      args: %{"membership_id" => membership_id, "notification_id" => notification_id}
    })
  end
end
