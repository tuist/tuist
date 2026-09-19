defmodule Atlas.Accounts.Workers.ScheduleAccountAttentionSuggestions do
  @moduledoc """
  Schedules account follow-up analysis for accounts with new evidence or a
  weekly review due.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Accounts

  @impl true
  def perform(%Oban.Job{}) do
    Accounts.list_attention_suggestion_candidate_ids()
    |> Enum.reduce_while({:ok, 0}, fn account_id, {:ok, count} ->
      case Accounts.enqueue_account_attention_suggestion_generation(account_id, "scheduled_review") do
        {:ok, _job} -> {:cont, {:ok, count + 1}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
