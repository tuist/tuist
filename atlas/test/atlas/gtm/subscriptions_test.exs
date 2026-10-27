defmodule Atlas.GTM.SubscriptionsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.GTM.Audience
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Subscriptions
  alias Atlas.GTM.Workers.DeliverAutomatedEmail

  setup do
    audience =
      %Audience{}
      |> Audience.changeset(%{name: "Email Digest", slug: "email-digest"})
      |> Repo.insert!()

    %{audience: audience}
  end

  test "re-requesting keeps a confirmed subscriber in the audience", %{audience: audience} do
    {:ok, subscriber} = Subscriptions.request_digest_subscription(%{"email" => "reader@example.com"})
    delivery = Repo.get_by!(Delivery, subscriber_id: subscriber.id, kind: "confirmation")
    token = delivery |> Subscriptions.confirmation_url() |> URI.parse() |> Map.fetch!(:path) |> Path.basename()
    {:ok, _confirmed} = Subscriptions.confirm(token)

    # A second submission must not demote the membership back to pending, or
    # the subscriber silently drops out of every broadcast.
    {:ok, _subscriber} = Subscriptions.request_digest_subscription(%{"email" => "reader@example.com"})

    membership = Repo.get_by!(AudienceMembership, audience_id: audience.id, subscriber_id: subscriber.id)
    assert membership.status == "subscribed"
    assert Audiences.subscribed_recipients(audience) != []
  end

  test "an unauthenticated request cannot rewrite an existing profile" do
    {:ok, subscriber} =
      Audiences.create_subscriber(%{
        "email" => "reader@example.com",
        "first_name" => "Real",
        "source" => "website",
        "user_group" => "enterprise"
      })

    {:ok, _subscriber} =
      Subscriptions.request_digest_subscription(%{
        "email" => "reader@example.com",
        "first_name" => "Spoofed",
        "user_group" => "spoofed",
        "source" => "spoofed",
        "metadata" => %{"injected" => true}
      })

    unchanged = Audiences.get_subscriber(subscriber.id)
    assert unchanged.first_name == "Real"
    assert unchanged.user_group == "enterprise"
    assert unchanged.source == "website"
    refute unchanged.metadata["injected"]
  end

  test "requests confirmation and activates the subscription", %{audience: audience} do
    assert {:ok, subscriber} =
             Subscriptions.request_digest_subscription(%{
               "email" => "reader@example.com",
               "first_name" => "Riley"
             })

    assert subscriber.status == "pending"
    delivery = Repo.get_by!(Delivery, subscriber_id: subscriber.id, kind: "confirmation")
    assert delivery.subject == "Confirm Email Digest subscription"
    assert_enqueued(worker: DeliverAutomatedEmail, args: %{"delivery_id" => delivery.id})

    token = delivery |> Subscriptions.confirmation_url() |> URI.parse() |> Map.fetch!(:path) |> Path.basename()
    assert {:ok, %{subscriber: confirmed}} = Subscriptions.confirm(token)
    assert confirmed.status == "subscribed"
    assert confirmed.confirmed_at

    membership = Repo.get_by!(AudienceMembership, audience_id: audience.id, subscriber_id: subscriber.id)
    assert membership.status == "subscribed"
  end

  test "unsubscribe links affect only the named audience", %{audience: audience} do
    {:ok, subscriber} = Audiences.create_subscriber(%{email: "leave@example.com", source: "test"})
    {:ok, _membership} = Audiences.add_subscriber(audience, subscriber)

    url = Subscriptions.unsubscribe_url(audience, subscriber)
    token = url |> URI.parse() |> Map.fetch!(:path) |> Path.basename()

    assert {:ok, %{subscriber: returned}} = Subscriptions.unsubscribe(token)
    assert returned.id == subscriber.id
    assert Audiences.get_subscriber(subscriber.id).status == "subscribed"
    refute Audiences.subscribed?(audience, subscriber)
  end
end
