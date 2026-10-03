defmodule Atlas.Outreach.Workers.ScheduleRecommendations do
  @moduledoc """
  Schedules guided outreach reviews for contacts with new account evidence.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Outreach

  @impl true
  def perform(%Oban.Job{}) do
    Outreach.list_recommendation_candidate_ids()
    |> Enum.reduce_while({:ok, 0}, fn contact_id, {:ok, count} ->
      case Outreach.enqueue_recommendation_generation(contact_id, "scheduled_review") do
        {:ok, _job} -> {:cont, {:ok, count + 1}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
