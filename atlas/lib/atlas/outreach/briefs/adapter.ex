defmodule Atlas.Outreach.Briefs.Adapter do
  import Ecto.Query

  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.Recommendation
  alias Atlas.Repo

  @no_reply_days 14

  def candidate_items(cadence, period) when cadence in ["daily", "weekly"] do
    recommendations = overdue_recommendations(period.end_at)
    attempts = unanswered_attempts(period.end_at)

    {:ok,
     %{
       summary:
         "#{length(recommendations)} outreach recommendations are due and #{length(attempts)} conversations exceeded the reply window.",
       items: recommendation_items(recommendations, period) ++ no_reply_items(attempts, period),
       generation_mode: "deterministic",
       generated_by_agent: nil
     }}
  end

  defp overdue_recommendations(now) do
    Recommendation
    |> where([recommendation], recommendation.status == "pending" and recommendation.due_at <= ^now)
    |> order_by([recommendation], asc: recommendation.due_at)
    |> preload([:account, :contact])
    |> Repo.all()
  end

  defp unanswered_attempts(now) do
    before = DateTime.add(now, -@no_reply_days, :day)

    MessageAttempt
    |> where([attempt], attempt.outcome == "pending" and attempt.sent_at <= ^before)
    |> order_by([attempt], asc: attempt.sent_at)
    |> preload([:account, :contact])
    |> Repo.all()
  end

  defp recommendation_items(recommendations, period) do
    Enum.map(recommendations, fn recommendation ->
      %{
        domain: "outreach",
        kind: "follow_up",
        title: "#{recommendation.contact.full_name}: #{recommendation.title}",
        detail: recommendation.guidance,
        severity:
          if(DateTime.before?(recommendation.due_at, DateTime.add(period.end_at, -7, :day)),
            do: "warning",
            else: "info"
          ),
        sensitivity: "internal",
        materiality_score: recommendation.confidence || Decimal.new("0.70"),
        confidence: recommendation.confidence,
        suggested_action: recommendation.guidance,
        completion_condition: "The recommended outreach step is completed or dismissed with a reason.",
        fingerprint: "outreach:recommendation:#{recommendation.contact_id}:#{recommendation.action_type}",
        source_type: "outreach_recommendation",
        source_id: recommendation.id,
        source_path: "/gtm/outreach/#{recommendation.contact_id}",
        due_at: recommendation.due_at,
        evidence: recommendation_evidence(recommendation)
      }
    end)
  end

  defp no_reply_items(attempts, period) do
    Enum.map(attempts, fn attempt ->
      %{
        domain: "outreach",
        kind: "expectation_missed",
        title: "No reply from #{attempt.contact.full_name}",
        detail:
          "The message sent on #{Calendar.strftime(attempt.sent_at, "%Y-%m-%d")} has no recorded reply after #{@no_reply_days} days.",
        severity: "warning",
        sensitivity: "internal",
        materiality_score: Decimal.new("0.78"),
        suggested_action: "Decide whether to follow up, nurture, or stop outreach.",
        completion_condition: "A follow-up decision is recorded for this conversation.",
        fingerprint: "outreach:no_reply:#{attempt.id}",
        source_type: "outreach_message_attempt",
        source_id: attempt.id,
        source_path: "/gtm/outreach/#{attempt.contact_id}",
        due_at: DateTime.add(period.end_at, 3, :day),
        evidence: [
          %{
            record_type: "outreach_message_attempt",
            record_id: attempt.id,
            source_class: "observed",
            observation: "Message sent at #{DateTime.to_iso8601(attempt.sent_at)} with no recorded response"
          }
        ]
      }
    end)
  end

  defp recommendation_evidence(%Recommendation{evidence: %{"items" => items}}) when is_list(items) do
    Enum.flat_map(items, fn item ->
      case item["event_id"] do
        id when is_binary(id) ->
          [
            %{
              record_type: "account_event",
              record_id: id,
              source_class: "observed",
              observation: item["observation"] || "Account event"
            }
          ]

        _id ->
          []
      end
    end)
  end

  defp recommendation_evidence(_recommendation), do: []
end
