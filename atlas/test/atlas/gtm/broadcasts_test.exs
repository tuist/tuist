defmodule Atlas.GTM.BroadcastsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.GTM.Audience
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Workers.DeliverBroadcast

  test "queues an immutable delivery snapshot and background job" do
    {audience, subscriber} = audience_with_subscriber!()

    assert {:ok, broadcast} =
             Broadcasts.queue_broadcast(audience, %{
               subject: "August update",
               body_markdown: "Hello from **Atlas**."
             })

    assert broadcast.status == "pending"
    assert broadcast.recipients_count == 1
    assert_enqueued(worker: DeliverBroadcast, args: %{"broadcast_id" => broadcast.id})

    delivery = Repo.get_by!(Delivery, broadcast_id: broadcast.id)
    assert delivery.recipient_email == subscriber.email
    assert delivery.status == "pending"
  end

  test "rejects a broadcast when the audience has no active recipients" do
    audience = insert_audience!()

    assert {:error, changeset} =
             Broadcasts.queue_broadcast(audience, %{subject: "Nobody", body_markdown: "Hello"})

    assert "has no subscribed recipients" in errors_on(changeset).audience_id
  end

  test "audits a direct delivery without an audience or a dashboard path" do
    delivery =
      %Delivery{}
      |> Delivery.changeset(%{
        kind: "direct",
        recipient_email: "direct-#{System.unique_integer([:positive])}@example.com",
        subject: "Your pricing is changing",
        status: "pending"
      })
      |> Repo.insert!()

    assert {:ok, _updated} =
             Broadcasts.update_delivery(delivery, %{
               status: "delivered",
               provider_message_id: "<message@mail.tuist.dev>"
             })

    activity = Repo.get_by!(Activity, action: "gtm_delivery.delivered", target_id: delivery.id)

    assert Map.fetch!(activity.metadata, "audience_id") == nil
    assert Map.fetch!(activity.metadata, "broadcast_id") == nil
    assert Map.fetch!(activity.metadata, "error") == nil
    assert activity.metadata["kind"] == "direct"

    refute Map.has_key?(activity.metadata, "path")
    assert is_nil(Audit.serialize(activity).target.path)
  end

  defp audience_with_subscriber! do
    audience = insert_audience!()

    subscriber =
      %Subscriber{}
      |> Subscriber.changeset(%{email: "broadcast@example.com", source: "test", status: "subscribed"})
      |> Repo.insert!()

    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)
    {audience, subscriber}
  end

  defp insert_audience! do
    %Audience{}
    |> Audience.changeset(%{name: "Digest", slug: "digest"})
    |> Repo.insert!()
  end
end
