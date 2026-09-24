defmodule Atlas.GTM.Workers.ResumeStalledDeliveriesTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Broadcast
  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Workers.DeliverAutomatedEmail
  alias Atlas.GTM.Workers.DeliverBroadcast
  alias Atlas.GTM.Workers.DeliverDirectEmail
  alias Atlas.GTM.Workers.ResumeStalledDeliveries

  setup do
    audience =
      %Audience{}
      |> Audience.changeset(%{name: "Email Digest", slug: "email-digest"})
      |> Repo.insert!()

    subscriber =
      %Subscriber{}
      |> Subscriber.changeset(%{email: "reader@example.com", source: "atlas", status: "subscribed"})
      |> Repo.insert!()

    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)

    %{audience: audience, subscriber: subscriber}
  end

  defp stalled_broadcast(audience, subscriber, delivery_attrs \\ %{}) do
    broadcast =
      %Broadcast{audience_id: audience.id}
      |> Broadcast.changeset(%{
        subject: "Issue 1",
        body_markdown: "Hello.",
        from_name: "Tuist",
        from_email: "pedro@tuist.dev",
        status: "sending"
      })
      |> Repo.insert!()

    delivery =
      %Delivery{broadcast_id: broadcast.id, audience_id: audience.id, subscriber_id: subscriber.id}
      |> Delivery.changeset(
        Map.merge(
          %{
            kind: "broadcast",
            recipient_email: subscriber.email,
            subject: "Issue 1",
            status: "pending"
          },
          delivery_attrs
        )
      )
      |> Repo.insert!()

    # Backdate both rows so the sweeper sees them as stalled rather than running.
    long_ago = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.truncate(:second)
    naive_long_ago = DateTime.to_naive(long_ago)

    Repo.update_all(from(b in Broadcast, where: b.id == ^broadcast.id), set: [updated_at: long_ago])
    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: [updated_at: naive_long_ago])

    %{broadcast: broadcast, delivery: delivery}
  end

  test "re-queues a broadcast whose delivery run was discarded", %{audience: audience, subscriber: subscriber} do
    %{broadcast: broadcast} = stalled_broadcast(audience, subscriber)

    assert {:ok, %{broadcasts: 1}} = perform_job(ResumeStalledDeliveries, %{})
    assert_enqueued(worker: DeliverBroadcast, args: %{"broadcast_id" => broadcast.id})
  end

  test "re-queues a broadcast with failed deliveries still under the attempt ceiling", %{
    audience: audience,
    subscriber: subscriber
  } do
    %{broadcast: broadcast} =
      stalled_broadcast(audience, subscriber, %{status: "failed", error: "provider down", attempts: 2})

    assert {:ok, %{broadcasts: 1}} = perform_job(ResumeStalledDeliveries, %{})
    assert_enqueued(worker: DeliverBroadcast, args: %{"broadcast_id" => broadcast.id})
  end

  test "leaves a broadcast alone once every recipient exhausted its attempts", %{
    audience: audience,
    subscriber: subscriber
  } do
    stalled_broadcast(audience, subscriber, %{
      status: "failed",
      error: "mailbox does not exist",
      attempts: Broadcasts.max_delivery_attempts()
    })

    assert {:ok, %{broadcasts: 0}} = perform_job(ResumeStalledDeliveries, %{})
    refute_enqueued(worker: DeliverBroadcast)
  end

  test "leaves a delivered broadcast alone", %{audience: audience, subscriber: subscriber} do
    %{broadcast: broadcast} =
      stalled_broadcast(audience, subscriber, %{status: "delivered", delivered_at: DateTime.utc_now()})

    Repo.update_all(from(b in Broadcast, where: b.id == ^broadcast.id), set: [status: "sent"])

    assert {:ok, %{broadcasts: 0}} = perform_job(ResumeStalledDeliveries, %{})
    refute_enqueued(worker: DeliverBroadcast)
  end

  test "leaves a run that is still in progress alone", %{audience: audience, subscriber: subscriber} do
    broadcast =
      %Broadcast{audience_id: audience.id}
      |> Broadcast.changeset(%{
        subject: "Issue 1",
        body_markdown: "Hello.",
        from_name: "Tuist",
        from_email: "pedro@tuist.dev",
        status: "sending"
      })
      |> Repo.insert!()

    %Delivery{broadcast_id: broadcast.id, audience_id: audience.id, subscriber_id: subscriber.id}
    |> Delivery.changeset(%{
      kind: "broadcast",
      recipient_email: subscriber.email,
      subject: "Issue 1",
      status: "pending"
    })
    |> Repo.insert!()

    assert {:ok, %{broadcasts: 0}} = perform_job(ResumeStalledDeliveries, %{})
    refute_enqueued(worker: DeliverBroadcast)
  end

  test "re-queues a stalled welcome delivery", %{audience: audience, subscriber: subscriber} do
    delivery =
      %Delivery{audience_id: audience.id, subscriber_id: subscriber.id}
      |> Delivery.changeset(%{
        kind: "welcome",
        recipient_email: subscriber.email,
        subject: "Welcome to Tuist",
        status: "failed",
        error: "provider down",
        attempts: 1
      })
      |> Repo.insert!()

    long_ago = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.truncate(:second)
    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: [updated_at: DateTime.to_naive(long_ago)])

    assert {:ok, %{deliveries: 1}} = perform_job(ResumeStalledDeliveries, %{})
    assert_enqueued(worker: DeliverAutomatedEmail, args: %{"delivery_id" => delivery.id})
  end

  test "re-queues a stalled direct delivery on its own worker" do
    delivery =
      %Delivery{}
      |> Delivery.changeset(%{
        kind: "direct",
        recipient_email: "recipient@example.com",
        subject: "Your Tuist pricing is changing",
        status: "failed",
        error: "provider down",
        attempts: 1,
        metadata: %{"body_markdown" => "Your price changes on 22 October 2026."}
      })
      |> Repo.insert!()

    long_ago = DateTime.utc_now() |> DateTime.add(-2, :day) |> DateTime.truncate(:second)
    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: [updated_at: DateTime.to_naive(long_ago)])

    assert {:ok, %{deliveries: 1}} = perform_job(ResumeStalledDeliveries, %{})
    assert_enqueued(worker: DeliverDirectEmail, args: %{"delivery_id" => delivery.id})
    refute_enqueued(worker: DeliverAutomatedEmail)
  end

  test "does not count a broadcast that already has a job queued", %{audience: audience, subscriber: subscriber} do
    %{broadcast: broadcast} = stalled_broadcast(audience, subscriber)

    {:ok, _job} = %{"broadcast_id" => broadcast.id} |> DeliverBroadcast.new() |> Oban.insert()

    assert {:ok, %{broadcasts: 0}} = perform_job(ResumeStalledDeliveries, %{})
  end
end
