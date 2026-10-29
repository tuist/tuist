defmodule Atlas.GTM.Workers.DeliverBroadcastTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Workers.DeliverBroadcast

  test "delivers the current subscribed recipients and finalizes the broadcast" do
    audience =
      %Audience{}
      |> Audience.changeset(%{name: "Product news", slug: "product-news"})
      |> Repo.insert!()

    subscriber =
      %Subscriber{}
      |> Subscriber.changeset(%{email: "delivery@example.com", first_name: "Riley", source: "test"})
      |> Repo.insert!()

    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)

    {:ok, broadcast} =
      Broadcasts.queue_broadcast(audience, %{
        subject: "A useful update",
        body_markdown: "The release is ready."
      })

    assert :ok = perform_job(DeliverBroadcast, %{"broadcast_id" => broadcast.id})

    delivered = Broadcasts.get_broadcast(broadcast.id)
    assert delivered.status == "sent"
    assert delivered.delivered_count == 1
    assert delivered.failed_count == 0

    delivery = Repo.get_by!(Delivery, broadcast_id: broadcast.id)
    assert delivery.status == "delivered"
    assert delivery.delivered_at
  end

  test "counts a failed attempt and re-sends only the undelivered recipient on the next run" do
    audience =
      %Audience{}
      |> Audience.changeset(%{name: "Product news", slug: "product-news"})
      |> Repo.insert!()

    for email <- ["first@example.com", "second@example.com"] do
      subscriber =
        %Subscriber{}
        |> Subscriber.changeset(%{email: email, source: "test"})
        |> Repo.insert!()

      {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)
    end

    {:ok, broadcast} =
      Broadcasts.queue_broadcast(audience, %{subject: "Issue 1", body_markdown: "Hello."})

    # The provider drops the second recipient, which is the "delivery to an
    # audience dropped part way through" case.
    stub(Atlas.Mailer, :deliver, fn email ->
      case email.to do
        [{_name, "second@example.com"}] -> {:error, :provider_unavailable}
        _other -> {:ok, %{id: "provider-message-id"}}
      end
    end)

    assert {:error, :one_or_more_deliveries_failed} =
             perform_job(DeliverBroadcast, %{"broadcast_id" => broadcast.id})

    delivered = Repo.get_by!(Delivery, broadcast_id: broadcast.id, recipient_email: "first@example.com")
    failed = Repo.get_by!(Delivery, broadcast_id: broadcast.id, recipient_email: "second@example.com")
    assert delivered.status == "delivered"
    assert failed.status == "failed"
    assert failed.attempts == 1
    assert Broadcasts.get_broadcast(broadcast.id).status == "failed"

    # The retry re-sends only the recipient that never made it.
    stub(Atlas.Mailer, :deliver, fn email ->
      assert [{_name, "second@example.com"}] = email.to
      {:ok, %{id: "provider-message-id"}}
    end)

    assert :ok = perform_job(DeliverBroadcast, %{"broadcast_id" => broadcast.id})

    resent = Repo.get_by!(Delivery, broadcast_id: broadcast.id, recipient_email: "second@example.com")
    assert resent.status == "delivered"

    assert Repo.get_by!(Delivery, broadcast_id: broadcast.id, recipient_email: "first@example.com").status ==
             "delivered"

    finalized = Broadcasts.get_broadcast(broadcast.id)
    assert finalized.status == "sent"
    assert finalized.delivered_count == 2
    assert finalized.failed_count == 0
  end

  test "gives up on a recipient that exhausted its attempts" do
    audience =
      %Audience{}
      |> Audience.changeset(%{name: "Product news", slug: "product-news"})
      |> Repo.insert!()

    subscriber =
      %Subscriber{}
      |> Subscriber.changeset(%{email: "bounces@example.com", source: "test"})
      |> Repo.insert!()

    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)

    {:ok, broadcast} =
      Broadcasts.queue_broadcast(audience, %{subject: "Issue 1", body_markdown: "Hello."})

    Repo.update_all(from(d in Delivery, where: d.broadcast_id == ^broadcast.id),
      set: [status: "failed", attempts: Broadcasts.max_delivery_attempts()]
    )

    stub(Atlas.Mailer, :deliver, fn _email -> flunk("must not retry an exhausted recipient") end)

    assert {:error, :one_or_more_deliveries_failed} =
             perform_job(DeliverBroadcast, %{"broadcast_id" => broadcast.id})
  end

  test "skips a recipient who unsubscribed after the snapshot was created" do
    audience =
      %Audience{}
      |> Audience.changeset(%{name: "Release notes", slug: "release-notes"})
      |> Repo.insert!()

    subscriber =
      %Subscriber{}
      |> Subscriber.changeset(%{email: "skip@example.com", source: "test"})
      |> Repo.insert!()

    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)
    {:ok, broadcast} = Broadcasts.queue_broadcast(audience, %{subject: "Release", body_markdown: "Ready."})
    {:ok, _membership} = Audiences.unsubscribe(audience, subscriber)

    assert :ok = perform_job(DeliverBroadcast, %{"broadcast_id" => broadcast.id})
    assert Repo.get_by!(Delivery, broadcast_id: broadcast.id).status == "skipped"
    assert Broadcasts.get_broadcast(broadcast.id).status == "sent"
  end
end
