defmodule Atlas.Outreach.MessageLearning do
  @moduledoc """
  Builds cautious, evidence-backed lessons from prior outreach messages.
  """

  import Ecto.Query

  alias Atlas.Accounts.Contact
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Repo

  @minimum_sample_size 5
  @attempt_limit 250
  @no_reply_after_days 14
  @dimensions ~w(message_kind message_intent personalization_source call_to_action)a

  def context(%Contact{}) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@no_reply_after_days, :day) |> DateTime.truncate(:second)

    attempts =
      MessageAttempt
      |> where([attempt], attempt.outcome != "pending" or attempt.sent_at <= ^cutoff)
      |> order_by([attempt], desc: attempt.sent_at)
      |> limit(^@attempt_limit)
      |> Repo.all()
      |> Enum.map(&evaluated_attempt(&1, cutoff))

    %{
      total_evaluated: length(attempts),
      minimum_sample_size: @minimum_sample_size,
      lessons: lessons(attempts),
      examples: examples(attempts)
    }
  end

  def empty do
    %{
      total_evaluated: 0,
      minimum_sample_size: @minimum_sample_size,
      lessons: [],
      examples: []
    }
  end

  defp evaluated_attempt(%MessageAttempt{outcome: "pending"} = attempt, _cutoff), do: %{attempt | outcome: "no_reply"}

  defp evaluated_attempt(attempt, _cutoff), do: attempt

  defp lessons(attempts) do
    @dimensions
    |> Enum.flat_map(&dimension_lessons(attempts, &1))
    |> Enum.sort_by(fn lesson -> {-lesson.positive_replies, -lesson.replies, -lesson.sent} end)
  end

  defp dimension_lessons(attempts, dimension) do
    attempts
    |> Enum.group_by(&Map.get(&1, dimension))
    |> Enum.reject(fn {value, grouped} -> is_nil(value) or length(grouped) < @minimum_sample_size end)
    |> Enum.map(fn {value, grouped} -> summarize(dimension, value, grouped) end)
  end

  defp summarize(dimension, value, attempts) do
    %{
      dimension: Atom.to_string(dimension),
      value: value,
      sent: length(attempts),
      replies: Enum.count(attempts, &(&1.outcome in ~w(replied positive_reply objection not_interested))),
      positive_replies: Enum.count(attempts, &(&1.outcome == "positive_reply")),
      negative_replies: Enum.count(attempts, &(&1.outcome in ~w(objection not_interested))),
      no_replies: Enum.count(attempts, &(&1.outcome == "no_reply"))
    }
  end

  defp examples(attempts) do
    attempts
    |> Enum.take(8)
    |> Enum.map(fn attempt ->
      %{
        outcome: attempt.outcome,
        message_kind: attempt.message_kind,
        message_intent: attempt.message_intent,
        personalization_source: attempt.personalization_source,
        call_to_action: attempt.call_to_action,
        sent_subject: attempt.sent_subject,
        sent_message: attempt.sent_message
      }
    end)
  end
end
