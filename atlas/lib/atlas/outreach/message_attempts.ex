defmodule Atlas.Outreach.MessageAttempts do
  @moduledoc """
  Connects an outbound message to the response it produced.
  """

  import Atlas.Outreach.Util, only: [attr: 3, normalize_optional_text: 1]
  import Ecto.Query

  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.Recommendation
  alias Atlas.Repo

  def track(%Contact{} = contact, %Event{kind: "message_sent"} = event, attrs) do
    recommendation = recommendation_for(contact, attr(attrs, "recommendation_id", :recommendation_id))
    strategy = message_strategy(recommendation)

    %MessageAttempt{
      contact_id: contact.id,
      account_id: contact.account_id,
      recommendation_id: recommendation && recommendation.id,
      sent_event_id: event.id,
      sender_id: normalize_optional_text(attr(attrs, "sender_id", :sender_id))
    }
    |> MessageAttempt.changeset(%{
      channel: normalize_optional_text(attr(attrs, "channel", :channel)) || "linkedin",
      message_kind: message_kind(recommendation),
      message_intent: strategy["message_intent"],
      personalization_source: strategy["personalization_source"],
      call_to_action: strategy["call_to_action"],
      proposed_subject: proposed_subject(recommendation),
      proposed_message: recommendation && recommendation.draft_message,
      sent_subject: normalize_optional_text(attr(attrs, "subject", :subject)),
      sent_message: event.body,
      outcome: "pending",
      sent_at: event.occurred_at
    })
    |> Repo.insert()
  end

  def track(%Contact{} = contact, %Event{kind: "message_received"} = event, attrs) do
    outcome = normalize_response_outcome(attr(attrs, "response_outcome", :response_outcome))

    # A booked meeting can follow an earlier reply to the same message.
    open_outcomes = if outcome == "meeting_booked", do: ~w(pending replied positive_reply), else: ~w(pending)

    attempt =
      MessageAttempt
      |> where(
        [attempt],
        attempt.contact_id == ^contact.id and attempt.outcome in ^open_outcomes and
          attempt.sent_at <= ^event.occurred_at
      )
      |> order_by([attempt], desc: attempt.sent_at, desc: attempt.inserted_at)
      |> limit(1)
      |> Repo.one()

    case attempt do
      nil ->
        {:ok, nil}

      %MessageAttempt{} = attempt ->
        attempt
        |> MessageAttempt.outcome_changeset(%{
          outcome: outcome,
          outcome_at: event.occurred_at,
          response_event_id: event.id
        })
        |> Repo.update()
    end
  end

  def track(%Contact{}, %Event{}, _attrs), do: {:ok, nil}

  @doc """
  Sends, replies, positive replies and booked meetings per sender and channel.
  Pending messages are not counted as replies.
  """
  def summary(opts \\ []) do
    since = DateTime.add(DateTime.utc_now(), -Keyword.get(opts, :days, 90), :day)

    MessageAttempt
    |> where([attempt], attempt.sent_at >= ^since)
    |> join(:left, [attempt], sender in assoc(attempt, :sender))
    |> group_by([attempt, sender], [sender.id, sender.name, sender.email, attempt.channel])
    |> select([attempt, sender], %{
      sender: coalesce(sender.name, sender.email),
      channel: attempt.channel,
      sent: count(attempt.id),
      replies: filter(count(attempt.id), attempt.outcome not in ["pending", "no_reply"]),
      positive_replies: filter(count(attempt.id), attempt.outcome in ["positive_reply", "meeting_booked"]),
      meetings: filter(count(attempt.id), attempt.outcome == "meeting_booked")
    })
    |> order_by([attempt], desc: count(attempt.id))
    |> Repo.all()
    |> Enum.map(fn row ->
      Map.merge(row, %{
        sender: row.sender || "Unknown",
        reply_rate: rate(row.replies, row.sent),
        meeting_rate: rate(row.meetings, row.sent)
      })
    end)
  end

  defp rate(_count, 0), do: nil
  defp rate(count, total), do: count / total

  defp recommendation_for(_contact, nil), do: nil

  defp recommendation_for(contact, recommendation_id) when is_binary(recommendation_id) do
    case Repo.get(Recommendation, recommendation_id) do
      %Recommendation{contact_id: contact_id} = recommendation when contact_id == contact.id -> recommendation
      _recommendation -> nil
    end
  end

  defp recommendation_for(_contact, _recommendation_id), do: nil

  defp message_strategy(%Recommendation{metadata: %{"message_strategy" => strategy}}) when is_map(strategy),
    do: strategy

  defp message_strategy(_recommendation), do: %{}

  defp message_kind(%Recommendation{action_type: action_type}) when action_type in ~w(inmail message reply follow_up),
    do: action_type

  defp message_kind(_recommendation), do: "manual"

  defp proposed_subject(%Recommendation{action_type: "inmail", draft_subject: subject}), do: subject
  defp proposed_subject(_recommendation), do: nil

  defp normalize_response_outcome(outcome) do
    outcome = normalize_optional_text(outcome)
    if outcome in MessageAttempt.response_outcomes(), do: outcome, else: "replied"
  end
end
