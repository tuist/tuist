defmodule Atlas.Outreach.MessageLearningTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.MessageLearning
  alias Atlas.Repo

  test "only exposes aggregate lessons after the minimum sample size" do
    contact = insert_contact!()

    Enum.each(
      ["positive_reply", "positive_reply", "replied", "not_interested"],
      &insert_attempt!(contact, &1)
    )

    assert %{total_evaluated: 4, lessons: []} = MessageLearning.context(contact)

    insert_attempt!(contact, "no_reply")

    learning = MessageLearning.context(contact)

    assert learning.total_evaluated == 5

    assert %{
             sent: 5,
             replies: 4,
             positive_replies: 2,
             negative_replies: 1,
             no_replies: 1
           } =
             Enum.find(
               learning.lessons,
               &(&1.dimension == "personalization_source" and &1.value == "recipient_message")
             )

    assert Enum.any?(learning.examples, &(&1.outcome == "positive_reply"))
    assert Enum.any?(learning.examples, &(&1.outcome == "no_reply"))
    assert Enum.all?(learning.examples, &(&1.sent_subject == "Trust in build feedback"))
  end

  defp insert_contact! do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "message-learning:#{System.unique_integer([:positive])}",
        name: "Learning Platforms",
        primary_domain: "learning.example",
        segment: :prospect
      })
      |> Repo.insert!()

    %Contact{account_id: account.id}
    |> Contact.outreach_changeset(%{
      full_name: "Jordan Lee",
      email: "jordan-#{System.unique_integer([:positive])}@example.com",
      outreach_enrolled_at: ~U[2026-07-01 09:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_attempt!(contact, outcome) do
    number = System.unique_integer([:positive])

    event =
      %Event{account_id: contact.account_id, contact_id: contact.id}
      |> Event.changeset(%{
        external_id: "learning-message-#{number}",
        source: "linkedin",
        kind: "message_sent",
        title: "Message sent",
        body: "How does your team decide which build feedback to trust?",
        occurred_at: ~U[2026-07-01 10:00:00Z]
      })
      |> Repo.insert!()

    %MessageAttempt{
      contact_id: contact.id,
      account_id: contact.account_id,
      sent_event_id: event.id
    }
    |> MessageAttempt.changeset(%{
      channel: "linkedin",
      message_kind: "inmail",
      message_intent: "understand_problem",
      personalization_source: "recipient_message",
      call_to_action: "question",
      sent_subject: "Trust in build feedback",
      sent_message: event.body,
      outcome: outcome,
      sent_at: event.occurred_at
    })
    |> Repo.insert!()
  end
end
