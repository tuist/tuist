defmodule Atlas.GTM.Workers.DeliverDirectEmailTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Swoosh.TestAssertions

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.DirectEmails
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Workers.DeliverDirectEmail

  @attrs %{
    "recipient_email" => "recipient@example.com",
    "recipient_name" => "Riley",
    "subject" => "Your Tuist pricing is changing",
    "body_markdown" => "Your price changes on 22 October 2026."
  }

  defp queue!(attrs \\ @attrs) do
    {:ok, %{delivery: delivery}} = DirectEmails.queue(attrs)
    delivery
  end

  # Audience slugs and subscriber emails are uniquely indexed, so two modules
  # sharing a literal serialize on each other's uncommitted index entry.
  defp insert_audience! do
    suffix = System.unique_integer([:positive])

    %Audience{}
    |> Audience.changeset(%{name: "Audience #{suffix}", slug: "audience-#{suffix}"})
    |> Repo.insert!()
  end

  defp unique_email, do: "recipient-#{System.unique_integer([:positive])}@example.com"

  test "delivers the email and marks the delivery" do
    delivery = queue!()

    assert :ok = perform_job(DeliverDirectEmail, %{"delivery_id" => delivery.id})

    delivered = Repo.get!(Delivery, delivery.id)
    assert delivered.status == "delivered"
    assert delivered.delivered_at

    assert_email_sent(fn email ->
      refute email.html_body =~ "Unsubscribe"
      refute Map.has_key?(email.headers, "List-Unsubscribe")
      assert email.to == [{"Riley", "recipient@example.com"}]
      assert email.subject == "Your Tuist pricing is changing"
    end)
  end

  test "delivers to a recipient who unsubscribed from every audience" do
    audience = insert_audience!()

    subscriber =
      %Subscriber{}
      |> Subscriber.changeset(%{email: unique_email(), source: "atlas"})
      |> Repo.insert!()

    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)
    {:ok, _unsubscribed} = Audiences.unsubscribe(audience, subscriber)

    delivery = queue!(Map.put(@attrs, "recipient_email", subscriber.email))

    assert :ok = perform_job(DeliverDirectEmail, %{"delivery_id" => delivery.id})
    assert Repo.get!(Delivery, delivery.id).status == "delivered"
    assert_email_sent(fn email -> assert email.to == [{"Riley", subscriber.email}] end)
  end

  test "records the provider message id" do
    stub(Atlas.Mailer, :deliver, fn _email -> {:ok, %{id: "provider-message-id"}} end)
    delivery = queue!()

    assert :ok = perform_job(DeliverDirectEmail, %{"delivery_id" => delivery.id})
    assert Repo.get!(Delivery, delivery.id).provider_message_id == "provider-message-id"
  end

  test "counts a failed attempt and re-sends on the next run" do
    stub(Atlas.Mailer, :deliver, fn _email -> {:error, :provider_unavailable} end)
    delivery = queue!()

    assert {:error, :provider_unavailable} = perform_job(DeliverDirectEmail, %{"delivery_id" => delivery.id})

    failed = Repo.get!(Delivery, delivery.id)
    assert failed.status == "failed"
    assert failed.attempts == 1
    assert failed.error =~ "provider_unavailable"

    stub(Atlas.Mailer, :deliver, fn _email -> {:ok, %{id: "provider-message-id"}} end)

    assert :ok = perform_job(DeliverDirectEmail, %{"delivery_id" => delivery.id})
    assert Repo.get!(Delivery, delivery.id).status == "delivered"
  end

  test "does not send twice for a delivery that already went out" do
    delivery = queue!()
    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: [status: "delivered"])

    reject(&Atlas.Mailer.deliver/1)

    assert :ok = perform_job(DeliverDirectEmail, %{"delivery_id" => delivery.id})
  end

  test "cancels a job whose delivery is gone" do
    assert {:cancel, :delivery_not_found} =
             perform_job(DeliverDirectEmail, %{"delivery_id" => Ecto.UUID.generate()})
  end

  test "cancels a job pointed at a delivery of another kind" do
    audience = insert_audience!()

    subscriber =
      %Subscriber{}
      |> Subscriber.changeset(%{email: unique_email(), source: "atlas"})
      |> Repo.insert!()

    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)

    {:ok, broadcast} =
      Broadcasts.queue_broadcast(audience, %{subject: "Issue 1", body_markdown: "Hello."})

    delivery = Repo.get_by!(Delivery, broadcast_id: broadcast.id)

    assert {:cancel, :delivery_not_found} = perform_job(DeliverDirectEmail, %{"delivery_id" => delivery.id})
  end
end
