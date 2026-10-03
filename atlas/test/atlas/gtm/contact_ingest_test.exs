defmodule Atlas.GTM.ContactIngestTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.GTM.Audience
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.ContactIngest
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Workers.DeliverAutomatedEmail
  alias Atlas.GTM.Workers.PostAudienceMemberNotification

  setup do
    signups =
      %Audience{}
      |> Audience.changeset(%{
        name: "Users",
        slug: "users",
        source_id: "cm0loopslistid"
      })
      |> Repo.insert!()

    %{signups: signups}
  end

  # The payload mirrors what the PostHog destination sends to Loops on an
  # identify event.
  defp posthog_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "email" => "signup@example.com",
        "userId" => "01H8XYZ",
        "firstName" => "Sam",
        "lastName" => "Builder",
        "userGroup" => "developer",
        "source" => "posthog"
      },
      overrides
    )
  end

  test "creates a subscriber and queues the welcome email" do
    assert {:ok, result} = ContactIngest.upsert_contact(posthog_payload())

    assert result.created
    subscriber = result.subscriber
    assert subscriber.email == "signup@example.com"
    assert subscriber.first_name == "Sam"
    assert subscriber.user_group == "developer"
    assert subscriber.source == "posthog"
    assert subscriber.status == "subscribed"
    assert subscriber.metadata["userId"] == "01H8XYZ"

    delivery = Repo.get_by!(Delivery, subscriber_id: subscriber.id, kind: "welcome")
    membership = Repo.get_by!(AudienceMembership, audience_id: delivery.audience_id, subscriber_id: subscriber.id)
    assert_enqueued(worker: DeliverAutomatedEmail, args: %{"delivery_id" => delivery.id})

    assert_enqueued(
      worker: PostAudienceMemberNotification,
      args: %{"membership_id" => membership.id}
    )
  end

  test "subscribes to the audience matching the Loops mailing list id", %{signups: signups} do
    payload = posthog_payload(%{"mailingLists" => %{"cm0loopslistid" => true}})

    assert {:ok, result} = ContactIngest.upsert_contact(payload)
    assert result.mailing_lists == ["cm0loopslistid"]
    assert result.unknown_mailing_lists == []

    membership = Repo.get_by!(AudienceMembership, audience_id: signups.id, subscriber_id: result.subscriber.id)
    assert membership.status == "subscribed"
  end

  test "falls back to the audience slug and reports unknown lists", %{signups: signups} do
    payload = posthog_payload(%{"mailingLists" => %{"users" => true, "not-a-list" => true}})

    assert {:ok, result} = ContactIngest.upsert_contact(payload)
    assert result.mailing_lists == ["users"]
    assert result.unknown_mailing_lists == ["not-a-list"]
    assert Repo.get_by!(AudienceMembership, audience_id: signups.id, subscriber_id: result.subscriber.id)
  end

  test "unsubscribes from a mailing list set to false", %{signups: signups} do
    assert {:ok, %{subscriber: subscriber}} =
             ContactIngest.upsert_contact(posthog_payload(%{"mailingLists" => %{"cm0loopslistid" => true}}))

    assert {:ok, _result} =
             ContactIngest.upsert_contact(posthog_payload(%{"mailingLists" => %{"cm0loopslistid" => false}}))

    membership = Repo.get_by!(AudienceMembership, audience_id: signups.id, subscriber_id: subscriber.id)
    assert membership.status == "unsubscribed"
  end

  test "keeps custom properties in the metadata and merges across calls" do
    assert {:ok, _first} = ContactIngest.upsert_contact(posthog_payload(%{"plan" => "free"}))
    assert {:ok, result} = ContactIngest.upsert_contact(posthog_payload(%{"postHog" => true}))

    refute result.created
    assert result.subscriber.metadata["plan"] == "free"
    assert result.subscriber.metadata["postHog"] == true
  end

  test "does not queue a second welcome email when the contact is identified again" do
    assert {:ok, %{subscriber: subscriber}} = ContactIngest.upsert_contact(posthog_payload())
    assert {:ok, _second} = ContactIngest.upsert_contact(posthog_payload(%{"firstName" => "Samuel"}))

    assert [_only_one] = Repo.all(from delivery in Delivery, where: delivery.subscriber_id == ^subscriber.id)
  end

  test "does not announce an audience member twice when a contact is identified again" do
    assert {:ok, %{subscriber: subscriber}} = ContactIngest.upsert_contact(posthog_payload())
    membership = Repo.get_by!(AudienceMembership, subscriber_id: subscriber.id)

    assert_enqueued(worker: PostAudienceMemberNotification, args: %{"membership_id" => membership.id})

    assert {:ok, %{created: false}} = ContactIngest.upsert_contact(posthog_payload(%{"firstName" => "Samuel"}))

    assert [job] = all_enqueued(worker: PostAudienceMemberNotification)
    assert job.args["membership_id"] == membership.id
    assert is_binary(job.args["notification_id"])
  end

  test "an identify event does not resubscribe somebody who unsubscribed" do
    assert {:ok, %{subscriber: subscriber}} = ContactIngest.upsert_contact(posthog_payload())
    {:ok, _updated} = Audiences.update_subscriber(subscriber, %{"status" => "unsubscribed"})

    assert {:ok, result} = ContactIngest.upsert_contact(posthog_payload())
    assert result.subscriber.status == "unsubscribed"
  end

  test "an explicit subscribed false unsubscribes the contact and sends nothing" do
    assert {:ok, result} = ContactIngest.upsert_contact(posthog_payload(%{"subscribed" => false}))
    assert result.subscriber.status == "unsubscribed"

    # Welcoming somebody who just opted out is the one thing this must not do.
    assert Repo.all(from delivery in Delivery, where: delivery.subscriber_id == ^result.subscriber.id) == []
    refute_enqueued(worker: DeliverAutomatedEmail)
  end

  test "reports a mailing list as unknown when the audience cannot be resolved" do
    payload = posthog_payload(%{"mailingLists" => %{"missing-list" => true}})

    assert {:ok, result} = ContactIngest.upsert_contact(payload)
    assert result.mailing_lists == []
    assert result.unknown_mailing_lists == ["missing-list"]
  end

  test "requires an email" do
    assert {:error, :email_missing} = ContactIngest.upsert_contact(%{"firstName" => "Sam"})
    assert {:error, :email_missing} = ContactIngest.upsert_contact(%{"email" => "  "})
  end
end
